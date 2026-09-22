ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoClickerTweak
AutoClickerTweak_FILES = Tweak.xm
AutoClickerTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-module-import-in-extern-c -Wno-incomplete-implementation
AutoClickerTweak_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
AutoClickerTweak_PRIVATE_FRAMEWORKS = IOKit GraphicsServices
AutoClickerTweak_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard || true"
