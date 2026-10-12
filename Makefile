# Tasks — Task-Killer / RAM frei für iPod touch 4 (iOS 6.1, ARMv7), Theos.
TARGET = iphone:clang:7.1:5.0
ARCHS  = armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Tasks
Tasks_FILES = $(wildcard src/*.m)
Tasks_FRAMEWORKS = UIKit CoreGraphics QuartzCore Foundation
Tasks_CFLAGS = -fobjc-arc -O2 -Wall -Isrc

TOOL_NAME = tkkill
tkkill_FILES = src/tkkill.c
tkkill_CFLAGS = -Wall

include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/tool.mk
