/*
 * Copyright (c) 2020, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

// NOTE: The bundled `nvtx3.hpp` (cudf vendored copy) is an OLD NVTX v3 header
// that is incompatible with the NVTX shipped in CUDA >= 12 (causes a cascade of
// "identifier ... is undefined" / "expected an operator" compile errors).
// NVTX ranges are profiling-only and have no effect on functional correctness,
// so we stub them out instead of pulling in the conflicting header.

namespace cudf {
/**
 * @brief Tag type for libcudf's NVTX domain.
 */
struct libcudf_domain {
  static constexpr char const* name{"libcudf"};  ///< Name of the libcudf domain
};

/**
 * @brief No-op stand-in for an NVTX range in the libcudf domain.
 */
struct thread_range {
  thread_range() = default;
  explicit thread_range(char const*) {}
};

}  // namespace cudf

/**
 * @brief No-op replacement for the NVTX function-range macro.
 *
 * Originally expanded to `NVTX3_FUNC_RANGE_IN(cudf::libcudf_domain)`. Disabled to
 * keep the build independent of the vendored NVTX header on CUDA >= 12.
 */
#define CUDF_FUNC_RANGE() ((void)0)
