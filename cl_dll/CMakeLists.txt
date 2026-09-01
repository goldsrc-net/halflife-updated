# Begin special case stuff for dynamic libraries included with the game
# vgui and SDL2 are dynamic libraries that are load-time linked by the client
# For Windows this requires us to link with the import libraries
# For Linux this requires the .so files to be located next to the client
# so that the path embedded in the resulting client.so is a filename without any path component to it,
# so that when the library is loaded its path is resolved relative to the executable (hl_linux)
# The actual .so files are next to hl_linux so that's where the paths must point to.
# This is how it was done in the original Linux makefiles as well
# DO NOT DO THIS FOR ANY OTHER LIBRARIES YOU USE! If you must ship a dynamic library you should use the same approach used for OpenAL.

# VGUI linkage — 32-bit (i386/win32) load-time links Valve's shared vgui (the real GoldSrc
# engine hosts vgui and has no client-hosted path). 64-bit targets (Xash3D-FWGS) static-link
# openvgui instead — see the HALFLIFE_VGUI_STATIC block further below. Ported from
# goldsrc-net/mod-ts (cl_dll/CMakeLists.txt @ 94c0bba).
# SDL2 is confined to the 32-bit Linux client: on 64-bit, input is fed by the engine's push
# callbacks (IN_ClientLookEvent / IN_ClientMoveEvent in inputw32.cpp), so the 64-bit client
# links no libSDL2.
set(HALFLIFE_VGUI_STATIC OFF)
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
	set(HALFLIFE_VGUI_STATIC ON)
endif()

if(NOT HALFLIFE_VGUI_STATIC)
	# 32-bit: dynamic Valve vgui, load-time linked (unchanged).
	add_library(vgui SHARED IMPORTED)
	target_include_directories(vgui INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/../utils/vgui/include)

	if (WIN32)
		set_target_properties(vgui PROPERTIES IMPORTED_IMPLIB "${CMAKE_CURRENT_SOURCE_DIR}/../utils/vgui/lib/win32_vc16/vgui.lib")
	else()
		# Copy the game-provided vgui next to the client so the embedded DT_NEEDED path
		# resolves relative to the engine at runtime.
		configure_file(../linux/release/vgui${CMAKE_SHARED_LIBRARY_SUFFIX} ${CMAKE_CURRENT_BINARY_DIR}/vgui${CMAKE_SHARED_LIBRARY_SUFFIX} COPYONLY)
		set_target_properties(vgui PROPERTIES IMPORTED_LOCATION "${CMAKE_CURRENT_BINARY_DIR}/vgui${CMAKE_SHARED_LIBRARY_SUFFIX}")
	endif()

	# SDL2 — GoldSrc reads mouse-look via SDL_GetRelativeMouseState (matches Valve's client;
	# see inputw32.cpp HL_INPUT_SDL). 32-bit only: load-time linked like vgui — the real
	# libSDL2 is supplied by the engine at runtime; DT_NEEDED points at the vendored SONAME.
	add_library(SDL2 SHARED IMPORTED)
	target_include_directories(SDL2 INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/../external)

	if (WIN32)
		set_target_properties(SDL2 PROPERTIES IMPORTED_IMPLIB "${CMAKE_CURRENT_SOURCE_DIR}/../lib/public/SDL2.lib")
	else()
		configure_file(../linux/libSDL2-2.0${CMAKE_SHARED_LIBRARY_SUFFIX}.0 ${CMAKE_CURRENT_BINARY_DIR}/libSDL2-2.0${CMAKE_SHARED_LIBRARY_SUFFIX}.0 COPYONLY)
		set_target_properties(SDL2 PROPERTIES IMPORTED_LOCATION "${CMAKE_CURRENT_BINARY_DIR}/libSDL2-2.0${CMAKE_SHARED_LIBRARY_SUFFIX}.0")
	endif()
endif()

if(HALFLIFE_VGUI_STATIC)
	# 64-bit xash targets: static-link VGUI so the client carries no vgui DT_NEEDED.
	# openvgui builds as libvgui.a, and the vgui_support shim (compiled with
	# INTERNAL_VGUI_SUPPORT) is linked in so the CLIENT itself exports InitVGUISupportAPI
	# — the engine then hosts VGUI *inside* the client (Xash3D FWGS client-hosted path)
	# rather than loading a separate vgui.so/vgui.dll.
	set(VGUI_STATIC ON CACHE BOOL "" FORCE)
	add_subdirectory(${CMAKE_SOURCE_DIR}/third_party/openvgui ${CMAKE_BINARY_DIR}/openvgui EXCLUDE_FROM_ALL)
	# openvgui's static archive gets linked into a shared object -> needs PIC.
	set_target_properties(vgui PROPERTIES POSITION_INDEPENDENT_CODE ON)

	# The shim is compiled in ISOLATION: its own include dirs (vendored xash engine
	# headers + VGUI headers) so it never resolves the HL SDK's same-named headers.
	add_library(vgui_support STATIC
		${CMAKE_SOURCE_DIR}/third_party/vgui_support/vgui_int.cpp
		${CMAKE_SOURCE_DIR}/third_party/vgui_support/vgui_surf.cpp
		${CMAKE_SOURCE_DIR}/third_party/vgui_support/vgui_input.cpp
		${CMAKE_SOURCE_DIR}/third_party/vgui_support/vgui_clip.cpp)
	target_compile_definitions(vgui_support PRIVATE INTERNAL_VGUI_SUPPORT $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:stricmp=strcasecmp _vsnprintf=vsnprintf>)
	target_include_directories(vgui_support PRIVATE
		${CMAKE_SOURCE_DIR}/third_party/vgui_support
		${CMAKE_SOURCE_DIR}/third_party/xash_headers
		${CMAKE_SOURCE_DIR}/third_party/openvgui/include
		${CMAKE_SOURCE_DIR}/utils/vgui/include)
	set_target_properties(vgui_support PROPERTIES POSITION_INDEPENDENT_CODE ON CXX_VISIBILITY_PRESET default)
	target_link_libraries(vgui_support PUBLIC vgui)
endif()

# End special case stuff for dynamic libraries included with the game

add_library(client SHARED)

set_target_properties(client PROPERTIES INSTALL_RPATH "$ORIGIN")

set_common_properties(client)

target_include_directories(client PRIVATE
	${CMAKE_CURRENT_SOURCE_DIR}
	hl
	particleman
	../dlls
	../common
	../game_shared
	../public
	../pm_shared
	../engine
	../utils/vgui/include)

target_compile_definitions(client PRIVATE
	CLIENT_DLL
	HL_DLL)

target_link_libraries(client PRIVATE
	$<$<PLATFORM_ID:Windows>:delayimp>
	$<$<PLATFORM_ID:Windows>:wsock32>)

if(NOT HALFLIFE_VGUI_STATIC)
	# 32-bit: dynamic vgui + SDL2, load-time linked (the .so files live next to the client).
	target_link_libraries(client PRIVATE vgui SDL2)
	if (UNIX)
		# Tell the linker to search for vgui.so and SDL2-2.0.so.0 in here
		target_link_directories(client PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
	endif()
else()
	# 64-bit: static openvgui + the vgui_support shim -> the client exports
	# InitVGUISupportAPI and carries no vgui DT_NEEDED. Nothing in the client
	# references InitVGUISupportAPI, so force the linker to keep it (otherwise it's
	# GC'd out of the static archive and the engine can't find the entry point).
	target_link_libraries(client PRIVATE vgui_support vgui)
	# The 64-bit client is hosted by Xash/Godot as the Valve base game itself (gamedir "valve"),
	# so the "not from a Valve game directory" refusal in CL_InitClient must be off here.
	target_compile_definitions(client PRIVATE HALFLIFE_ALLOW_VALVE_GAMEDIR)
	target_link_options(client PRIVATE
		$<$<PLATFORM_ID:Linux>:-Wl,-u,InitVGUISupportAPI>
		$<$<PLATFORM_ID:Windows>:/INCLUDE:InitVGUISupportAPI>)
endif()

target_link_options(client PRIVATE
	$<$<PLATFORM_ID:Darwin>:-framework Carbon>)

target_sources(client PRIVATE
	ammo.cpp
	ammohistory.cpp
	ammo_secondary.cpp
	battery.cpp
	cdll_int.cpp
	com_weapons.cpp
	death.cpp
	demo.cpp
	entity.cpp
	events.cpp
	ev_common.cpp
	ev_hldm.cpp
	flashlight.cpp
	GameStudioModelRenderer.cpp
	geiger.cpp
	health.cpp
	hud.cpp
	hud_msg.cpp
	hud_redraw.cpp
	hud_spectator.cpp
	hud_update.cpp
	input.cpp
	inputw32.cpp
	interpolation.cpp
	in_camera.cpp
	menu.cpp
	message.cpp
	saytext.cpp
	statusbar.cpp
	status_icons.cpp
	StudioModelRenderer.cpp
	studio_util.cpp
	text_message.cpp
	train.cpp
	tri.cpp
	util.cpp
	vgui_ClassMenu.cpp
	vgui_CustomObjects.cpp
	vgui_int.cpp
	vgui_MOTDWindow.cpp
	vgui_SchemeManager.cpp
	vgui_ScorePanel.cpp
	vgui_SpectatorPanel.cpp
	vgui_TeamFortressViewport.cpp
	vgui_teammenu.cpp
	view.cpp
	voice_status.cpp

	hl/hl_baseentity.cpp
	hl/hl_events.cpp
	hl/hl_objects.cpp
	hl/hl_weapons.cpp

	particleman/CBaseParticle.cpp
	particleman/CMiniMem.cpp
	particleman/CFrustum.cpp
	particleman/IParticleMan_Active.cpp

	../common/mathlib.cpp
	../common/parsemsg.cpp

	../dlls/crossbow.cpp
	../dlls/crowbar.cpp
	../dlls/egon.cpp
	../dlls/gauss.cpp
	../dlls/handgrenade.cpp
	../dlls/hornetgun.cpp
	../dlls/mp5.cpp
	../dlls/python.cpp
	../dlls/rpg.cpp
	../dlls/satchel.cpp
	../dlls/shotgun.cpp
	../dlls/squeakgrenade.cpp
	../dlls/tripmine.cpp
	../dlls/weapons_shared.cpp
	../dlls/glock.cpp

	../game_shared/filesystem_utils.cpp
	../game_shared/vgui_checkbutton2.cpp
	../game_shared/vgui_grid.cpp
	../game_shared/vgui_helpers.cpp
	../game_shared/vgui_listbox.cpp
	../game_shared/vgui_loadtga.cpp
	../game_shared/vgui_scrollbar2.cpp
	../game_shared/vgui_slider2.cpp
	../game_shared/voice_banmgr.cpp

	../pm_shared/pm_debug.cpp
	../pm_shared/pm_math.cpp
	../pm_shared/pm_shared.cpp

	../public/interface.cpp

	ammo.h
	ammohistory.h
	camera.h
	cl_dll.h
	cl_util.h
	com_weapons.h
	demo.h
	eventscripts.h
	ev_hldm.h
	GameStudioModelRenderer.h
	health.h
	hud.h
	hud_spectator.h
	interpolation.h
	in_defs.h
	kbutton.h
	particleman/CBaseParticle.h
	particleman/CFrustum.h
	particleman/IParticleMan_Active.h
	particleman/particleman.h
	particleman/particleman_internal.h
	particleman/CMiniMem.h
	StudioModelRenderer.h
	tri.h
	vgui_int.h
	vgui_SchemeManager.h
	vgui_ScorePanel.h
	vgui_SpectatorPanel.h
	view.h

	../common/beamdef.h
	../common/cl_entity.h
	../common/common_types.h
	../common/com_model.h
	../common/const.h
	../common/con_nprint.h
	../common/crc.h
	../common/cvardef.h
	../common/demo_api.h
	../common/director_cmds.h
	../common/dlight.h
	../common/dll_state.h
	../common/entity_state.h
	../common/entity_types.h
	../common/enums.h
	../common/event_api.h
	../common/event_args.h
	../common/event_flags.h
	../common/hltv.h
	../common/in_buttons.h
	../common/ivoicetweak.h
	../common/mathlib.h
	../common/netadr.h
	../common/net_api.h
	../common/parsemsg.h
	../common/particledef.h
	../common/Platform.h
	../common/PlatformHeaders.h
	../common/pmtrace.h
	../common/qfont.h
	../common/ref_params.h
	../common/r_efx.h
	../common/r_studioint.h
	../common/screenfade.h
	../common/Sequence.h
	../common/studio_event.h
	../common/triangleapi.h
	../common/usercmd.h
	../common/weaponinfo.h

	../dlls/cdll_dll.h

	../engine/APIProxy.h
	../engine/cdll_int.h
	../engine/custom.h
	../engine/customentity.h
	../engine/edict.h
	../engine/eiface.h
	../engine/progdefs.h
	../engine/progs.h
	../engine/shake.h
	../engine/studio.h

	../game_shared/filesystem_utils.h
	../game_shared/vgui_scrollbar2.h
	../game_shared/vgui_slider2.h
	../game_shared/voice_banmgr.h
	../game_shared/voice_status.h

	../pm_shared/pm_debug.h
	../pm_shared/pm_defs.h
	../pm_shared/pm_info.h
	../pm_shared/pm_materials.h
	../pm_shared/pm_movevars.h
	../pm_shared/pm_shared.h

	../public/interface.h)
