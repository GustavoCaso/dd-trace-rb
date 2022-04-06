#pragma once

#ifdef RUBY_2_1_WORKAROUND
#include <thread_native.h>
#else
#include <ruby/thread_native.h>
#endif

#include "extconf.h"

rb_nativethread_id_t pthread_id_for(VALUE thread);
int ddtrace_rb_profile_frames(VALUE thread, int start, int limit, VALUE *buff, int *lines, bool* is_ruby_frame);

// Ruby 3.0 finally added support for showing CFUNC frames (frames for methods written using native code)
// in stack traces gathered via `rb_profile_frames` (https://github.com/ruby/ruby/pull/3299).
// To access this information on older Rubies, beyond using our custom `ddtrace_rb_profile_frames` above, we also need
// to backport the Ruby 3.0+ version of `rb_profile_frame_method_name`.
#ifdef USE_BACKPORTED_RB_PROFILE_FRAME_METHOD_NAME
  VALUE ddtrace_rb_profile_frame_method_name(VALUE frame);
#else // Ruby > 3.0, just use the stock functionality
  #define ddtrace_rb_profile_frame_method_name rb_profile_frame_method_name
#endif
