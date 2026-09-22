ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoClickerTweak
AutoClickerTweak_FILES = Tweak.xm
AutoClickerTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
AutoClickerTweak_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore ImageIO MobileCoreServices
AutoClickerTweak_PRIVATE_FRAMEWORKS = IOKit GraphicsServices
AutoClickerTweak_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard || true"
