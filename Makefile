export TARGET = iphone:clang:latest:7.0
export ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TouchRecorderTweak

TouchRecorderTweak_FILES = Tweak.x
TouchRecorderTweak_CFLAGS = -fobjc-arc -Wno-error -Wno-deprecated-declarations
TouchRecorderTweak_FRAMEWORKS = UIKit Foundation CoreGraphics

# لم نعد بحاجة إلى GraphicsServices على الإطلاق
# TouchRecorderTweak_PRIVATE_FRAMEWORKS = 

INSTALL_TARGET_PROCESSES = all

include $(THEOS_MAKE_PATH)/tweak.mk
