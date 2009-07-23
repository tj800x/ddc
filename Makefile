
# targets:
#       all             -- build everything
#       deps            -- build dependencies
#	runtime		-- build the runtime system
#	external	-- build external libraries
#	libs		-- build base libraries
#
#       bin/ddc         -- build the compiler binary
#       bin/war2        -- build the test driver
#       bin/plate       -- build the boilerplate generator
#
#       clean           -- clean everything
#       cleanWar        -- clean libraries and tests, but leave the compiler build alone
#       cleanRuntime    -- clean the runtime system

# -- build everything
all	: src/Config/Config.hs bin/ddc bin/war bin/war2 runtime external

include make/build.mk

# -- Find Source Files ----------------------------------------------------------------------------
# -- files needing to be processed via alex
src_alex_x	=  $(shell find src -name "*.x" -follow)
src_alex_hs	=  $(patsubst %.x,%.hs,$(src_alex_x))

# -- files that are ready to compile
src_hs_existing	=  $(shell find src -name "*.hs" -follow)

# -- all .hs files in the src dir, including ones we need to preprocess.
src_hs_all	+= $(src_hs_existing)
src_hs_all	+= $(src_alex_hs)


# -- Dependencies ----------------------------------------------------------------------------------
.PHONY	: deps
deps	: make/Makefile.deps

make/Makefile.deps : src/Config/Config.hs $(src_hs_existing) 
	@echo "* Building dependencies"
	@$(GHC) -isrc -M $^ -dep-makefile -optdepmake/Makefile.deps $(GHC_INCDIRS)
	@rm -f make/Makefile.deps.bak
	@cp make/Makefile.deps make/Makefile.deps.inc
	@echo


# -- Boilerplate ----------------------------------------------------------------------------------
# -- build the boiler plate generator
bin/plate : tools/plate/Main.hs src/Config/Config.hs
	@echo "* Building boilerplate generator -------------------------------"
	$(GHC) $(GHC_FLAGS) -isrc -itools/plate -o bin/plate --make $^ 

# -- generate boilerplate
src/Source/Plate/Trans.hs : bin/plate src/Source/Plate/Trans.hs-stub src/Source/Exp.hs 
	@echo "* Generating boilerplate for $@"
	bin/plate src/Source/Exp.hs src/Source/Plate/Trans.hs-stub src/Source/Plate/Trans.hs
	@echo


# -- Link DDC -------------------------------------------------------------------------------------
# -- all the resulting .o files we'll get after compiling the .hs files
src_obj		=  $(patsubst %.hs,%.o,$(src_hs_existing))

bin/ddc	: make/Makefile.deps $(src_obj)
	@echo "* Linking $@"
	$(GHC) -o bin/ddc $(GHC_FLAGS) \
		-package unix -package mtl -package containers -package parsec -package regex-compat -package QuickCheck \
		$(src_obj)
	@echo	


# -- External libraries ---------------------------------------------------------------------------
.PHONY	: external
external : external/TinyPTC-X11-0.7.3/xshm.o

external/TinyPTC-X11-0.7.3/xshm.o : 
	@echo "* Building external libraries ----------------------------------"
	cd external/TinyPTC-X11-0.7.3; $(MAKE) CFLAGS="$(GCC_FLAGS)"
	@echo


# -- Runtime system -------------------------------------------------------------------------------
runtime_c = \
	$(shell ls runtime/*.c) \
	$(shell find runtime/Prim -name "*.c")

runtime_dep	= $(patsubst %.c,%.dep,$(runtime_c))
runtime_o	= $(patsubst %.c,%.o,$(runtime_c))

runtime/libddc-runtime.$(SHARED_SUFFIX) : $(runtime_o)
	@echo "* Linking $@"
	$(BUILD_SHARED) -o $@ $^
	@echo

runtime/libddc-runtime.a  : $(runtime_o)
	@echo "* Building $@"
	ar r $@ $^
	@echo

.PHONY  : runtime
runtime : $(runtime_dep) runtime/libddc-runtime.$(SHARED_SUFFIX) runtime/libddc-runtime.a


# -- Base Libraries --------------------------------------------------------------------------------
.PHONY	: libs
libs	: library/Prelude.di

library/Prelude.di : bin/ddc
	@echo "* Building base libraries --------------------------------------"
	bin/ddc -O -make library/Prelude.ds
	@touch library/Prelude.di
	@echo


# -- Test Driver -----------------------------------------------------------------------------------
war2_hs	= $(shell find tools/war2 -name "*.hs")

bin/war2 : $(war2_hs)
	$(GHC) $(GHC_FLAGS) -O2 -fglasgow-exts -threaded -fglasgow-exts \
		-isrc -itools/war2 --make tools/war2/Main.hs -o bin/war2


# -- Cleaning --------------------------------------------------------------------------------------
# -- clean objects in the runtime system
.PHONY : cleanRuntime
cleanRuntime :
	@echo "* Cleaning runtime"
	@find runtime \
		    	-name "*.o" \
		-o	-name "*.dep" \
		-o	-name "*.so" \
		-o  -name "*.dylib" \
		-o	-name "*.a" \
		-follow | xargs -n 1 rm -f


# -- clean up libraries and tests, but leave the compiler build alone
.PHONY  : cleanWar
cleanWar :
	@echo "* Cleaning war"
	@find library test demo \
			-name "*.dump-*.*"  \
		-o	-name "*.graph-*.dot" \
		-o	-name "*.di"    \
		-o	-name "*.gdl"   \
		-o	-name "*.o"     \
		-o	-name "*.ddc.c" \
		-o	-name "*.ddc.h" \
		-o	-name "*.bin"   \
		-o	-name "*.out"   \
		-o 	-name "*.diff"  \
		-o	-name "*.tix"   \
		-o	-name "*.compile.stderr" \
		-o	-name "*.compile.stdout" \
		-o	-name "*.stdout" \
		-o	-name "*.stderr" \
		-follow | xargs -n 1 rm -f


# -- clean up everything
.PHONY : clean
clean  : cleanWar cleanRuntime
	@echo "* Cleaning leftovers"
	@find . \
			-name "*.o" \
		-o	-name "*.so" \
		-o  -name "*.dylib" \
		-o	-name "*.hi" \
		-o	-name "*.hi-boot" \
		-o	-name "*.hcr" \
		-o	-name "*.td" \
		-o	-name "*.ti" \
		-o	-name "Makefile.deps" \
		-follow | xargs -n 1 rm -f
		
	@rm -f 	bin/* \
		make/Makefile.deps.bak 


include make/plate.mk
-include make/Makefile.deps.inc
-include runtime/*.dep
