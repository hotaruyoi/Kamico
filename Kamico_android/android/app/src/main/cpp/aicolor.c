// AI 上色原生实现：解码 → 灰度 → 缩放 → ORT 推理 → 色度上采样 →
// 亮度合成（带暗部屏蔽）→ JPEG 编码。
//
// 只通过 C ABI 暴露给 Dart（dart:ffi），不使用 JNI。
// 仅 arm64-v8a 链接 ONNX Runtime；其它 ABI 编译成返回错误的桩，
// 让 Dart 侧可以统一按「能力不可用」处理而不会在加载 .so 时崩溃。
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// CMake 用 C_VISIBILITY_PRESET hidden 编译，只导出下面的 aicolor_* 接口。
#define AICOLOR_API __attribute__((visibility("default")))

#ifdef AICOLOR_WITH_ORT

#include <onnxruntime_c_api.h>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include <pthread.h>
#include <stdint.h>

#define AICOLOR_MAX_SIDE 2048

static const OrtApi *g_api = NULL;
static OrtEnv *g_env = NULL;
static OrtSession *g_session = NULL;
static OrtSessionOptions *g_opts = NULL;
static OrtMemoryInfo *g_mem = NULL;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static int g_threads = 4;
static char g_err[512] = {0};

static void set_err(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(g_err, sizeof(g_err), fmt, ap);
  va_end(ap);
}

// 双线性缩放到 dw x dh，输入是灰度（每像素 1 字节）
static unsigned char *resize_gray(const unsigned char *src, int sw, int sh,
                                  int dw, int dh) {
  unsigned char *dst = (unsigned char *)malloc((size_t)dw * (size_t)dh);
  if (!dst) return NULL;
  for (int y = 0; y < dh; y++) {
    float fy = (y + 0.5f) * sh / dh - 0.5f;
    int y0 = (int)fy;
    if (y0 < 0) y0 = 0;
    int y1 = y0 + 1 < sh ? y0 + 1 : sh - 1;
    float wy = fy - y0;
    if (wy < 0) wy = 0;
    for (int x = 0; x < dw; x++) {
      float fx = (x + 0.5f) * sw / dw - 0.5f;
      int x0 = (int)fx;
      if (x0 < 0) x0 = 0;
      int x1 = x0 + 1 < sw ? x0 + 1 : sw - 1;
      float wx = fx - x0;
      if (wx < 0) wx = 0;
      float a = src[(size_t)y0 * sw + x0] * (1 - wx) +
                src[(size_t)y0 * sw + x1] * wx;
      float b = src[(size_t)y1 * sw + x0] * (1 - wx) +
                src[(size_t)y1 * sw + x1] * wx;
      dst[(size_t)y * dw + x] = (unsigned char)(a * (1 - wy) + b * wy + 0.5f);
    }
  }
  return dst;
}

// 暗部屏蔽：亮度低于 a 完全不上色，高于 b 完全上色，中间平滑过渡。
// 不做这层会把黑色线条染成暗红/暗紫。
static float smoothstep(float x, float a, float b) {
  float t = (x - a) / (b - a);
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  return t * t * (3 - 2 * t);
}

// 判断一页是否本来就是彩色的。
//
// 黑白的线稿页 R/G/B 三通道几乎相等，饱和度的平均值很低；彩页则明显偏高。
// 这里用「平均饱和度」做主判据（阈值 0.12）。在真实样本上彩页最低 0.178，
// 黑白页最高 0.053，两类完全不重叠。抽样按步长把样本压到约 256x256，
// 避免对 1440x2048 整页逐像素遍历。
static int looks_already_colored(const unsigned char *raw, int w, int h) {
  if (w <= 0 || h <= 0) return 0;
  int step = 1;
  while ((w / step) > 256 || (h / step) > 256) step++;
  long long samples = 0, saturation = 0;  // 饱和度和，单位千分比
  for (int y = 0; y < h; y += step) {
    const unsigned char *row = raw + (size_t)y * (size_t)w * 3;
    for (int x = 0; x < w; x += step) {
      const unsigned char *p = row + (size_t)x * 3;
      int r = p[0], g = p[1], b = p[2];
      int mx = r > g ? r : g;
      if (b > mx) mx = b;
      int mn = r < g ? r : g;
      if (b < mn) mn = b;
      if (mx < 1) mx = 1;
      saturation += (long long)((mx - mn) * 1000 / mx);
      samples++;
    }
  }
  if (samples <= 0) return 0;
  return (saturation / samples) >= 120 ? 1 : 0;
}

// stb 写入回调：把 JPEG 追加到一块可增长的内存里
typedef struct {
  unsigned char *data;
  size_t len;
  size_t cap;
  int failed;
} out_buf;

static void out_write(void *ctx, void *data, int size) {
  out_buf *b = (out_buf *)ctx;
  if (b->failed) return;
  size_t need = b->len + (size_t)size;
  if (need > b->cap) {
    size_t cap = b->cap ? b->cap : 65536;
    while (cap < need) cap *= 2;
    unsigned char *p = (unsigned char *)realloc(b->data, cap);
    if (!p) {
      b->failed = 1;
      return;
    }
    b->data = p;
    b->cap = cap;
  }
  memcpy(b->data + b->len, data, (size_t)size);
  b->len += (size_t)size;
}

AICOLOR_API int aicolor_init(const char *model_path, int threads, int use_arena,
                 char *err, int errcap) {
  pthread_mutex_lock(&g_lock);
  if (g_session) {
    pthread_mutex_unlock(&g_lock);
    if (err && errcap > 0) err[0] = 0;
    return 0;
  }
  g_err[0] = 0;
  g_api = OrtGetApiBase()->GetApi(ORT_API_VERSION);
  if (!g_api) {
    set_err("OrtGetApiBase 返回空，onnxruntime 版本不匹配");
    goto fail;
  }
  if (g_api->CreateEnv(ORT_LOGGING_LEVEL_ERROR, "aicolor", &g_env)) {
    set_err("CreateEnv 失败");
    goto fail;
  }
  if (g_api->CreateSessionOptions(&g_opts)) {
    set_err("CreateSessionOptions 失败");
    goto fail;
  }
  g_threads = threads > 0 ? (threads > 8 ? 8 : threads) : 4;
  {
    // 这三项失败不影响可用性，用默认值继续跑，只清掉 status。
    OrtStatus *st = NULL;
    st = g_api->SetIntraOpNumThreads(g_opts, g_threads);
    if (st) g_api->ReleaseStatus(st);
    st = g_api->SetSessionGraphOptimizationLevel(g_opts, ORT_ENABLE_ALL);
    if (st) g_api->ReleaseStatus(st);
    if (!use_arena) {
      st = g_api->DisableCpuMemArena(g_opts);
      if (st) g_api->ReleaseStatus(st);
    }
  }
  if (g_api->CreateSession(g_env, model_path, g_opts, &g_session)) {
    set_err("CreateSession 失败：模型无法加载或非法");
    goto fail;
  }
  if (g_api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &g_mem)) {
    set_err("CreateCpuMemoryInfo 失败");
    goto fail;
  }
  pthread_mutex_unlock(&g_lock);
  if (err && errcap > 0) err[0] = 0;
  return 0;

fail:
  if (err && errcap > 0) {
    strncpy(err, g_err, (size_t)errcap - 1);
    err[errcap - 1] = 0;
  }
  if (g_mem) { g_api->ReleaseMemoryInfo(g_mem); g_mem = NULL; }
  if (g_session) { g_api->ReleaseSession(g_session); g_session = NULL; }
  if (g_opts) { g_api->ReleaseSessionOptions(g_opts); g_opts = NULL; }
  if (g_env) { g_api->ReleaseEnv(g_env); g_env = NULL; }
  pthread_mutex_unlock(&g_lock);
  return -1;
}

AICOLOR_API int aicolor_run(const unsigned char *in, int in_len, int target_w, int target_h,
                int quality, unsigned char **out, int *out_len,
                int *already_colored, char *err, int errcap) {
  int rc = -1;
  unsigned char *raw = NULL, *gray = NULL, *small = NULL, *rgb = NULL;
  float *inp = NULL, *outp = NULL;
  OrtValue *iv = NULL, *ov = NULL;
  out_buf ob;
  memset(&ob, 0, sizeof(ob));
  if (already_colored) *already_colored = 0;
  int q = quality > 0 ? (quality > 100 ? 100 : quality) : 92;

  pthread_mutex_lock(&g_lock);
  if (!g_session || !g_api) {
    set_err("尚未初始化");
    goto done;
  }
  if (!in || in_len <= 0 || target_w <= 0 || target_h <= 0) {
    set_err("参数非法");
    goto done;
  }
  if (target_w > AICOLOR_MAX_SIDE || target_h > AICOLOR_MAX_SIDE) {
    set_err("推理尺寸超过上限 %d", AICOLOR_MAX_SIDE);
    goto done;
  }

  int sw = 0, sh = 0, sc = 0;
  raw = stbi_load_from_memory(in, in_len, &sw, &sh, &sc, 3);
  if (!raw) {
    set_err("图片解码失败：%s", stbi_failure_reason());
    goto done;
  }
  if (sw <= 0 || sh <= 0) {
    set_err("图片尺寸非法");
    goto done;
  }

  // 本来就是彩色的一页不做上色：模型会把已经着色的画面当成黑白线稿重新涂一遍，
  // 结果比原图更糟。原样编码返回，让上层把这页标记成「已彩色、已跳过」。
  if (looks_already_colored(raw, sw, sh)) {
    if (already_colored) *already_colored = 1;
    if (!stbi_write_jpg_to_func(out_write, &ob, sw, sh, 3, raw, q) || ob.failed) {
      set_err("JPEG 编码失败");
      goto done;
    }
    *out = ob.data;
    *out_len = (int)ob.len;
    ob.data = NULL;
    rc = 0;
    goto done;
  }

  gray = (unsigned char *)malloc((size_t)sw * (size_t)sh);
  if (!gray) {
    set_err("内存不足（灰度）");
    goto done;
  }
  for (size_t i = 0; i < (size_t)sw * (size_t)sh; i++) {
    int r = raw[i * 3], g = raw[i * 3 + 1], b = raw[i * 3 + 2];
    gray[i] = (unsigned char)((r * 77 + g * 150 + b * 29) >> 8);
  }

  small = resize_gray(gray, sw, sh, target_w, target_h);
  if (!small) {
    set_err("内存不足（缩放）");
    goto done;
  }

  size_t isz = (size_t)5 * (size_t)target_h * (size_t)target_w;
  inp = (float *)calloc(isz, sizeof(float));
  if (!inp) {
    set_err("内存不足（输入张量）");
    goto done;
  }
  for (size_t i = 0; i < (size_t)target_w * (size_t)target_h; i++) {
    inp[i] = small[i] / 255.0f;
  }

  int64_t shape[4] = {1, 5, target_h, target_w};
  if (g_api->CreateTensorWithDataAsOrtValue(
          g_mem, inp, isz * sizeof(float), shape, 4,
          ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &iv)) {
    set_err("CreateTensor 失败");
    goto done;
  }
  const char *in_names[] = {"input"};
  const char *out_names[] = {"rgb"};
  OrtStatus *st = g_api->Run(g_session, NULL, in_names,
                             (const OrtValue *const *)&iv, 1, out_names, 1, &ov);
  if (st) {
    set_err("推理失败：%s", g_api->GetErrorMessage(st));
    g_api->ReleaseStatus(st);
    goto done;
  }
  if (g_api->GetTensorMutableData(ov, (void **)&outp)) {
    set_err("取输出失败");
    goto done;
  }

  rgb = (unsigned char *)malloc((size_t)sw * (size_t)sh * 3);
  if (!rgb) {
    set_err("内存不足（合成）");
    goto done;
  }
  for (int y = 0; y < sh; y++) {
    float fy = (y + 0.5f) * target_h / sh - 0.5f;
    int y0 = (int)fy;
    if (y0 < 0) y0 = 0;
    int y1 = y0 + 1 < target_h ? y0 + 1 : target_h - 1;
    float wy = fy - y0;
    if (wy < 0) wy = 0;
    for (int x = 0; x < sw; x++) {
      float fx = (x + 0.5f) * target_w / sw - 0.5f;
      int x0 = (int)fx;
      if (x0 < 0) x0 = 0;
      int x1 = x0 + 1 < target_w ? x0 + 1 : target_w - 1;
      float wx = fx - x0;
      if (wx < 0) wx = 0;
      float ch[3];
      for (int c = 0; c < 3; c++) {
        float a = outp[(size_t)c * target_h * target_w + (size_t)y0 * target_w + x0] * (1 - wx) +
                  outp[(size_t)c * target_h * target_w + (size_t)y0 * target_w + x1] * wx;
        float b = outp[(size_t)c * target_h * target_w + (size_t)y1 * target_w + x0] * (1 - wx) +
                  outp[(size_t)c * target_h * target_w + (size_t)y1 * target_w + x1] * wx;
        ch[c] = a * (1 - wy) + b * wy;
      }
      float mean = (ch[0] + ch[1] + ch[2]) / 3.0f;
      float lum = gray[(size_t)y * sw + x] / 255.0f;
      float wgt = smoothstep(lum, 0.45f, 0.85f);
      for (int c = 0; c < 3; c++) {
        float v = lum + (ch[c] - mean) * wgt;
        if (v < 0) v = 0;
        if (v > 1) v = 1;
        rgb[((size_t)y * sw + x) * 3 + c] = (unsigned char)(v * 255.0f + 0.5f);
      }
    }
  }

  if (!stbi_write_jpg_to_func(out_write, &ob, sw, sh, 3, rgb, q) || ob.failed) {
    set_err("JPEG 编码失败");
    goto done;
  }
  *out = ob.data;
  *out_len = (int)ob.len;
  ob.data = NULL;
  rc = 0;

done:
  if (err && errcap > 0) {
    strncpy(err, g_err, (size_t)errcap - 1);
    err[errcap - 1] = 0;
  }
  if (rc != 0 && ob.data) free(ob.data);
  if (ov) g_api->ReleaseValue(ov);
  if (iv) g_api->ReleaseValue(iv);
  free(rgb);
  free(inp);
  free(small);
  free(gray);
  if (raw) stbi_image_free(raw);
  pthread_mutex_unlock(&g_lock);
  return rc;
}

AICOLOR_API void aicolor_free(void *p) { free(p); }

AICOLOR_API void aicolor_dispose(void) {
  pthread_mutex_lock(&g_lock);
  if (g_mem) { g_api->ReleaseMemoryInfo(g_mem); g_mem = NULL; }
  if (g_session) { g_api->ReleaseSession(g_session); g_session = NULL; }
  if (g_opts) { g_api->ReleaseSessionOptions(g_opts); g_opts = NULL; }
  if (g_env) { g_api->ReleaseEnv(g_env); g_env = NULL; }
  pthread_mutex_unlock(&g_lock);
}

AICOLOR_API int aicolor_is_ready(void) { return g_session ? 1 : 0; }

AICOLOR_API int aicolor_threads(void) { return g_threads; }

#else  // 非 arm64-v8a：编译成桩，避免 Dart 侧 .so 加载失败

AICOLOR_API int aicolor_init(const char *model_path, int threads, int use_arena,
                 char *err, int errcap) {
  (void)model_path;
  (void)threads;
  (void)use_arena;
  if (err && errcap > 0) strncpy(err, "当前 CPU 架构不支持 AI 上色", (size_t)errcap - 1);
  return -2;
}

AICOLOR_API int aicolor_run(const unsigned char *in, int in_len, int target_w, int target_h,
                int quality, unsigned char **out, int *out_len,
                int *already_colored, char *err, int errcap) {
  (void)in; (void)in_len; (void)target_w; (void)target_h; (void)quality;
  (void)out; (void)out_len; (void)already_colored;
  if (err && errcap > 0) strncpy(err, "当前 CPU 架构不支持 AI 上色", (size_t)errcap - 1);
  return -2;
}

AICOLOR_API void aicolor_free(void *p) { (void)p; }
AICOLOR_API void aicolor_dispose(void) {}
AICOLOR_API int aicolor_is_ready(void) { return 0; }
AICOLOR_API int aicolor_threads(void) { return 0; }

#endif
