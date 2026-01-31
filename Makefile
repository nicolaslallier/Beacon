.DEFAULT_GOAL := help

include makefiles/variables.mk
include makefiles/help.mk
include makefiles/lint.mk
include makefiles/compose.mk
include makefiles/library.mk
include makefiles/ssl.mk
include makefiles/ci.mk
include makefiles/release.mk
