# MinGW cross-build from WSL (llvm-mingw or system mingw-w64).
ROOT := $(abspath ../..)
OUT  := $(ROOT)/target/release
CXX  ?= x86_64-w64-mingw32-g++
CXXFLAGS := -O2 -s -static -static-libgcc -static-libstdc++ -DUNICODE=0 -D_WIN32_WINNT=0x0A00
LIBS := -ladvapi32 -lwtsapi32 -luserenv -lshell32

.PHONY: all clean

all: $(OUT)/rohomieo-broker.exe $(OUT)/rohomieo-broker-ctl.exe

$(OUT):
	mkdir -p $(OUT)

$(OUT)/rohomieo-broker.exe: RohomieoBrokerService.cpp protocol.h | $(OUT)
	$(CXX) $(CXXFLAGS) -o $@ RohomieoBrokerService.cpp $(LIBS)

$(OUT)/rohomieo-broker-ctl.exe: RohomieoClient.cpp protocol.h | $(OUT)
	$(CXX) $(CXXFLAGS) -o $@ RohomieoClient.cpp $(LIBS)

clean:
	rm -f $(OUT)/rohomieo-broker.exe $(OUT)/rohomieo-broker-ctl.exe
