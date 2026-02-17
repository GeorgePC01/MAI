//
//  main.m
//  MAI Helper - CEF subprocess
//
//  This is the helper process required by CEF on macOS.
//  Each renderer/GPU/utility process is a separate instance of this binary.
//  It dynamically loads the CEF framework and forwards execution to CEF's process handling.
//

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <libgen.h>

// Function pointer type for cef_execute_process
typedef struct _cef_main_args_t {
    int argc;
    char** argv;
} cef_main_args_t;

typedef int (*cef_execute_process_func)(const cef_main_args_t*, void*, void*);
typedef const char* (*cef_api_hash_func)(int, int);

int main(int argc, char* argv[]) {
    @autoreleasepool {
        // Step 1: Compute path to CEF framework relative to helper executable
        // Helper is at: MAI.app/Contents/Frameworks/MAI Helper.app/Contents/MacOS/MAI Helper
        // Framework is at: MAI.app/Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework
        uint32_t exec_path_size = 0;
        _NSGetExecutablePath(NULL, &exec_path_size);
        char* exec_path = (char*)malloc(exec_path_size);
        _NSGetExecutablePath(exec_path, &exec_path_size);

        char* parent_dir = dirname(exec_path);
        char framework_path[4096];
        snprintf(framework_path, sizeof(framework_path),
                 "%s/../../../Chromium Embedded Framework.framework/Chromium Embedded Framework",
                 parent_dir);
        free(exec_path);

        // Step 2: Dynamically load the CEF framework
        void* lib = dlopen(framework_path, RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST);
        if (!lib) {
            fprintf(stderr, "MAI Helper: Failed to load CEF framework: %s\n", dlerror());
            return 1;
        }

        // Step 3: Configure API version
        cef_api_hash_func api_hash = (cef_api_hash_func)dlsym(lib, "cef_api_hash");
        if (api_hash) {
            // CEF_API_VERSION_EXPERIMENTAL = 999999
            api_hash(999999, 0);
        }

        // Step 4: Resolve cef_execute_process
        cef_execute_process_func exec_process = (cef_execute_process_func)dlsym(lib, "cef_execute_process");
        if (!exec_process) {
            fprintf(stderr, "MAI Helper: Failed to resolve cef_execute_process: %s\n", dlerror());
            dlclose(lib);
            return 1;
        }

        // Step 5: Execute CEF subprocess logic
        cef_main_args_t mainArgs = {};
        mainArgs.argc = argc;
        mainArgs.argv = argv;

        int exitCode = exec_process(&mainArgs, NULL, NULL);

        dlclose(lib);
        return exitCode;
    }
}
