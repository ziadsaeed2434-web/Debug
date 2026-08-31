THEOS_DEVICE_IP = localhost
THEOS_DEVICE_PORT = 2222
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RewardedDebugTweak

RewardedDebugTweak_FILES = Tweak.xm DebugOverlay.m
RewardedDebugTweak_FRAMEWORKS = UIKit Foundation CoreGraphics WebKit SystemConfiguration
RewardedDebugTweak_EXTRA_FRAMEWORKS += 
RewardedDebugTweak_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard || true"
