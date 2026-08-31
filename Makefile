TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CodeBySMSHook

CodeBySMSHook_FILES = Tweak.x
CodeBySMSHook_FRAMEWORKS = Foundation UIKit CoreLocation CoreGraphics WebKit AdSupport
CodeBySMSHook_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
