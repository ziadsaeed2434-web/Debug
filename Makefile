export TARGET = iphone:clang:latest:14.0
export ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TouchRecorderTweak

TouchRecorderTweak_FILES = Tweak.x
TouchRecorderTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-implicit-enum-enum-cast
TouchRecorderTweak_FRAMEWORKS = UIKit Foundation
TouchRecorderTweak_PRIVATE_FRAMEWORKS = GraphicsServices

INSTALL_TARGET_PROCESSES = all

include $(THEOS_MAKE_PATH)/tweak.mk
