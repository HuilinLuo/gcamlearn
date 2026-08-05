#' Configure environment variables required to build/load gcamwrapper
#'
#' `gcamwrapper` (and the underlying GCAM C++ core) locate their
#' dependencies via environment variables at build/load time. This function
#' sets those variables for the current R session. All paths are arguments
#' (nothing is hardcoded) so the same function works across machines/OSes;
#' unset arguments fall back to environment variables of the same name if
#' already set (e.g. via `.Renviron`), and an argument left `NULL` with no
#' existing environment variable is simply skipped with a warning.
#'
#' @param gcam_include,gcam_lib Paths to the GCAM core `objects` include
#'   directory and its build/lib directory.
#' @param boost_include,boost_lib Paths to Boost headers and compiled libs.
#' @param tbb_include,tbb_lib Paths to Intel TBB headers and libs.
#' @param eigen_include Path to the Eigen headers.
#' @param java_include,java_include_win32,java_lib Paths to the JDK include
#'   directories (`java_include_win32` only needed on Windows) and the
#'   directory containing `jvm.dll`/`libjvm.so`.
#' @param jars_lib Path (glob) to the GCAM Java jars, e.g. `".../jars/*"`.
#' @param python_include Path to the Python include directory.
#' @param osname_lowercase One of `"win32"`, `"linux"`, `"macosx"`.
#' @param extra_path Character vector of additional directories to prepend
#'   to `PATH` (e.g. directories containing required DLLs/shared libs).
#' @param load_gcamwrapper If `TRUE` (default), calls `library(gcamwrapper)`
#'   after setting environment variables.
#'
#' @return Invisibly, the named list of environment variables that were set.
#' @export
#'
#' @examples
#' \dontrun{
#' setup_gcam_env(
#'   gcam_include = "C:/gcam-core/cvs/objects",
#'   gcam_lib     = "C:/gcam-core/cvs/objects/build/linux",
#'   boost_include = "C:/gcam-core/libs/boost-lib",
#'   boost_lib     = "C:/gcam-core/libs/boost-lib/stage/lib",
#'   tbb_include   = "C:/rtools44/mingw64/include/oneapi",
#'   tbb_lib       = "C:/rtools44/mingw64/bin",
#'   eigen_include = "C:/gcam-core/libs/eigen",
#'   java_include        = "C:/jdk-18/include",
#'   java_include_win32  = "C:/jdk-18/include/win32",
#'   java_lib            = "C:/jdk-18/bin/server",
#'   jars_lib      = "C:/gcam-core/libs/jars/*",
#'   python_include = "C:/Python310/include",
#'   osname_lowercase = "win32",
#'   extra_path = c("C:/rtools44/mingw64/bin", "C:/jdk-18/bin/server")
#' )
#' }
setup_gcam_env <- function(gcam_include = NULL,
                            gcam_lib = NULL,
                            boost_include = NULL,
                            boost_lib = NULL,
                            tbb_include = NULL,
                            tbb_lib = NULL,
                            eigen_include = NULL,
                            java_include = NULL,
                            java_include_win32 = NULL,
                            java_lib = NULL,
                            jars_lib = NULL,
                            python_include = NULL,
                            osname_lowercase = c("win32", "linux", "macosx"),
                            extra_path = NULL,
                            load_gcamwrapper = TRUE) {
  osname_lowercase <- match.arg(osname_lowercase)

  vars <- list(
    GCAM_INCLUDE       = gcam_include,
    GCAM_LIB           = gcam_lib,
    BOOST_INCLUDE      = boost_include,
    BOOST_LIB          = boost_lib,
    TBB_INCLUDE        = tbb_include,
    TBB_LIB            = tbb_lib,
    EIGEN_INCLUDE      = eigen_include,
    JAVA_INCLUDE       = java_include,
    JAVA_INCLUDE_WIN32 = java_include_win32,
    JAVA_LIB           = java_lib,
    OSNAME_LOWERCASE   = osname_lowercase,
    JARS_LIB           = jars_lib,
    PYTHON_INCLUDE     = python_include
  )

  # fall back to any already-set environment variable of the same name
  for (nm in names(vars)) {
    if (is.null(vars[[nm]])) {
      existing <- Sys.getenv(nm, unset = NA)
      if (!is.na(existing) && nzchar(existing)) {
        vars[[nm]] <- existing
      }
    }
  }

  missing <- names(vars)[vapply(vars, is.null, logical(1))]
  if (length(missing) > 0) {
    warning(
      "The following gcamwrapper environment variables were not set (no ",
      "argument given and no existing env var found): ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  to_set <- vars[!vapply(vars, is.null, logical(1))]
  if (length(to_set) > 0) {
    do.call(Sys.setenv, to_set)
  }

  if (!is.null(extra_path) && length(extra_path) > 0) {
    Sys.setenv(PATH = paste(
      paste(extra_path, collapse = .Platform$path.sep),
      Sys.getenv("PATH"),
      sep = .Platform$path.sep
    ))
  }

  if (isTRUE(load_gcamwrapper)) {
    if (!requireNamespace("gcamwrapper", quietly = TRUE)) {
      stop(
        "gcamwrapper is not installed/loadable. Environment variables have ",
        "been set; install/build gcamwrapper and try again, or call ",
        "setup_gcam_env(..., load_gcamwrapper = FALSE) to skip loading.",
        call. = FALSE
      )
    }
    library(gcamwrapper)
    message("gcamwrapper environment configured and loaded.")
  }

  invisible(vars)
}
