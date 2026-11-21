#pragma once

// Published strings remain valid for the process lifetime.
extern "C" const char* kudroid_current_log_dir(void);
extern "C" const char* kudroid_host_log_dir(void);
const char* bridgeDocumentsDirectory(void);
bool bridgeConfigureLogPaths(const char* documents, const char* root);
bool bridgeSelectAppLogDirectory(const char* package);
bool bridgeValidPackageIdentifier(const char* package);
void bridgeRememberDocumentsDirectory(const char* documents);
void bridgeClearCurrentLogFiles(void);
