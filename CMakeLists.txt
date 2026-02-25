cmake_minimum_required(VERSION 3.22)
project(AuphonicApp VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0" CACHE STRING "Minimum macOS version")

include(FetchContent)

FetchContent_Declare(
    JUCE
    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
    GIT_TAG 8.0.4
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(JUCE)

juce_add_gui_app(AuphonicApp
    PRODUCT_NAME "AuphonicApp"
    BUNDLE_ID "com.auphonic.app"
    COMPANY_NAME "Auphonic"
    ICON_BIG "${CMAKE_CURRENT_SOURCE_DIR}/Packaging/icon.png"
    ICON_SMALL "${CMAKE_CURRENT_SOURCE_DIR}/Packaging/icon.png"
)

target_sources(AuphonicApp PRIVATE
    Source/Main.cpp
    Source/MainComponent.cpp
    Source/AuphonicApiClient.cpp
    Source/SettingsManager.cpp
    Source/ProcessingWorkflow.cpp
    Source/SettingsComponent.cpp
    Source/PresetListComponent.cpp
    Source/ManualOptionsComponent.cpp
    Source/StatusComponent.cpp
    Source/FileDropComponent.cpp
    Source/CreditsComponent.cpp
    Source/MacStyleLookAndFeel.cpp
    Source/AudioPlayerComponent.cpp
)

target_compile_definitions(AuphonicApp PRIVATE
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_APPLICATION_NAME_STRING="$<TARGET_PROPERTY:AuphonicApp,JUCE_PRODUCT_NAME>"
    JUCE_APPLICATION_VERSION_STRING="$<TARGET_PROPERTY:AuphonicApp,JUCE_VERSION>"
)

target_link_libraries(AuphonicApp PRIVATE
    juce::juce_core
    juce::juce_events
    juce::juce_gui_basics
    juce::juce_gui_extra
    juce::juce_audio_basics
    juce::juce_audio_devices
    juce::juce_audio_formats
    juce::juce_audio_utils
    juce::juce_recommended_config_flags
    juce::juce_recommended_warning_flags
)
