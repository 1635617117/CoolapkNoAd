ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CoolapkNoAd

CoolapkNoAd_FILES = Tweak.xm
CoolapkNoAd_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
CoolapkNoAd_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
