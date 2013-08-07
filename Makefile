# Directory where the lua executable can be found
LUA_DIR=/usr/bin/

# Lua intepreter
LUA=lua

# Lua compiler
LUAC=luac

# Luaenc executable
LUAENC=/usr/local/bin/luaenc

# compile lua script and encrypt it if luaenc exist
define compile_lua_script
	echo "lua script to be compiled: " 
	echo $1 
	$(LUAC) -o $@.$(EXT) $(1)
	if [ -e "$(LUAENC)" ]; then \
		$(LUAENC) $@.$(EXT) $@.$(EXT).enc xz; \
	fi
	echo "#!$(LUA_DIR)$(LUA)" > $@.$(EXT).sh
	if [ -e "$(LUAENC)" ]; then \
		cat $@.$(EXT).enc >> $@.$(EXT).sh; \
	else \
		cat $@.$(EXT) >> $@.$(EXT).sh; \
	fi
	chmod +x $@.$(EXT).sh 
endef

# the extension of the binaries, only overwrite this if LUAC is long and contains spaces (as it does in OpenWRT).
EXT=$(LUAC)

all: hora

hora: hora.lua
	@$(call compile_lua_script, hora.lua)

