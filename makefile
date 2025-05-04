CXX = cosmoc++
CFLAGS = -mcosmo -Iinclude/

FFMPEG_VERSION = 7.1

FFMPEG_URL_PREFIX = https://github.com/BtbN/FFmpeg-Builds/releases/download/latest
FFMPEG_BUILD_linux = ffmpeg-n$(FFMPEG_VERSION)-latest-linux64-gpl-$(FFMPEG_VERSION).tar.xz
FFMPEG_BUILD_windows = ffmpeg-n$(FFMPEG_VERSION)-latest-win64-gpl-$(FFMPEG_VERSION).zip

TMP_DIR = .download

FFMPEG_DEST = ffmpeg
FFMPEG_DEST_linux = $(FFMPEG_DEST)/linux
FFMPEG_DEST_windows = $(FFMPEG_DEST)/windows
FFMPEG_TARGETS_linux = $(FFMPEG_DEST_linux)/ffmpeg $(FFMPEG_DEST_linux)/ffprobe
FFMPEG_TARGETS_windows = $(FFMPEG_DEST_windows)/ffmpeg.exe $(FFMPEG_DEST_windows)/ffprobe.exe

.PHONY: all clean distclean

all: nikon-p950-vc.exe python.exe \
	$(FFMPEG_TARGETS_linux) $(FFMPEG_TARGETS_windows)

nikon-p950-vc.exe: main.cpp
	$(CXX) $(CFLAGS) -o nikon-p950-vc.exe main.cpp

python.exe:
	wget -O python.exe 'https://cosmo.zip/pub/cosmos/bin/python'
	chmod +x python.exe

clean:
	rm -rf nikon-p950-vc.exe*

distclean: clean
	rm -rf $(FFMPEG_DEST)

$(FFMPEG_TARGETS_linux):
	@echo "Downloading ffmpeg for Linux"
	mkdir -p $(TMP_DIR)

	if [ -f $(TMP_DIR)/$(FFMPEG_BUILD_linux) ]; then \
		echo "File $(TMP_DIR)/$(FFMPEG_BUILD_linux) already exists, skipping download."; \
	else \
		wget -O $(TMP_DIR)/$(FFMPEG_BUILD_linux) ${FFMPEG_URL_PREFIX}/${FFMPEG_BUILD_linux}; \
	fi

	mkdir -p $(FFMPEG_DEST_linux)
	tar xvf $(TMP_DIR)/$(FFMPEG_BUILD_linux) -C $(FFMPEG_DEST_linux) --wildcards --strip-components=2 '*/bin/ffmpeg' '*/bin/ffprobe'

$(FFMPEG_TARGETS_windows):
	@echo "Downloading ffmpeg for Windows"
	mkdir -p $(TMP_DIR)

	if [ -f $(TMP_DIR)/$(FFMPEG_BUILD_windows) ]; then \
		echo "File $(TMP_DIR)/$(FFMPEG_BUILD_windows) already exists, skipping download."; \
	else \
		wget -O $(TMP_DIR)/$(FFMPEG_BUILD_windows) ${FFMPEG_URL_PREFIX}/${FFMPEG_BUILD_windows}; \
	fi

	mkdir -p $(FFMPEG_DEST_windows)
	unzip -o $(TMP_DIR)/$(FFMPEG_BUILD_windows) -d $(TMP_DIR) '*/bin/ffmpeg.exe' '*/bin/ffprobe.exe'
	mv $(TMP_DIR)/*/bin/ffmpeg.exe $(FFMPEG_DEST_windows)/ffmpeg.exe
	mv $(TMP_DIR)/*/bin/ffprobe.exe $(FFMPEG_DEST_windows)/ffprobe.exe
