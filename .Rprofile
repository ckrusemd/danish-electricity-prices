# Batch commands use --vanilla and R_LIBS_USER; interactive sessions never restore.
project_library <- Sys.getenv("R_LIBS_USER", "/opt/electricity/library")
if (dir.exists(project_library)) .libPaths(c(project_library, .libPaths()))
rm(project_library)
