#include "AuphonicApiClient.h"

AuphonicApiClient::AuphonicApiClient (const juce::String& apiToken)
    : token (apiToken)
{
}

void AuphonicApiClient::setToken (const juce::String& newToken)
{
    token = newToken;
}

juce::URL AuphonicApiClient::makeUrl (const juce::String& endpoint) const
{
    return juce::URL (juce::String (baseUrl) + endpoint);
}

juce::String AuphonicApiClient::performGet (const juce::URL& url, int& statusCode)
{
    auto options = juce::URL::InputStreamOptions (juce::URL::ParameterHandling::inAddress)
        .withExtraHeaders ("Authorization: Bearer " + token)
        .withConnectionTimeoutMs (15000)
        .withStatusCode (&statusCode);

    if (auto stream = url.createInputStream (options))
        return stream->readEntireStreamAsString();

    return {};
}

juce::String AuphonicApiClient::performPost (const juce::URL& url, int& statusCode)
{
    auto options = juce::URL::InputStreamOptions (juce::URL::ParameterHandling::inPostData)
        .withExtraHeaders ("Authorization: Bearer " + token)
        .withConnectionTimeoutMs (30000)
        .withStatusCode (&statusCode);

    if (auto stream = url.createInputStream (options))
        return stream->readEntireStreamAsString();

    return {};
}

void AuphonicApiClient::fetchUserInfo (UserInfoCallback callback)
{
    juce::Thread::launch ([this, callback]
    {
        int statusCode = 0;
        auto url = makeUrl ("/user.json");
        auto response = performGet (url, statusCode);

        UserCredits credits;
        bool success = false;

        if (statusCode == 200)
        {
            auto json = juce::JSON::parse (response);
            auto data = json.getProperty ("data", juce::var());

            credits.credits = (double) data.getProperty ("credits", 0.0);
            credits.onetimeCredits = (double) data.getProperty ("onetime_credits", 0.0);
            credits.recurringCredits = (double) data.getProperty ("recurring_credits", 0.0);
            success = true;
        }

        juce::MessageManager::callAsync ([callback, success, statusCode, credits] { callback (success, statusCode, credits); });
    });
}

void AuphonicApiClient::fetchPresets (PresetsCallback callback)
{
    juce::Thread::launch ([this, callback]
    {
        int statusCode = 0;
        auto url = makeUrl ("/presets.json");
        auto response = performGet (url, statusCode);

        juce::Array<AuphonicPreset> presets;
        bool success = false;

        if (statusCode == 200)
        {
            auto json = juce::JSON::parse (response);
            if (auto* dataArray = json.getProperty ("data", {}).getArray())
            {
                for (auto& item : *dataArray)
                {
                    AuphonicPreset p;
                    p.uuid = item.getProperty ("uuid", "").toString();
                    p.name = item.getProperty ("preset_name", "").toString();
                    if (p.name.isEmpty())
                        p.name = item.getProperty ("name", "Unnamed").toString();
                    presets.add (p);
                }
                success = true;
            }
        }

        juce::MessageManager::callAsync ([callback, success, presets] { callback (success, presets); });
    });
}

void AuphonicApiClient::fetchPresetDetails (const juce::String& uuid,
                                              PresetDetailsCallback callback)
{
    juce::Thread::launch ([this, uuid, callback]
    {
        int statusCode = 0;
        auto url = makeUrl ("/preset/" + uuid + ".json");
        auto response = performGet (url, statusCode);

        juce::var algorithms;
        bool success = false;

        if (statusCode == 200)
        {
            auto json = juce::JSON::parse (response);
            algorithms = json.getProperty ("data", juce::var())
                              .getProperty ("algorithms", juce::var());
            success = true;
        }

        juce::MessageManager::callAsync ([callback, success, algorithms] { callback (success, algorithms); });
    });
}

void AuphonicApiClient::savePreset (const juce::String& name,
                                     const juce::var& settings,
                                     SavePresetCallback callback)
{
    juce::Thread::launch ([this, name, settings, callback]
    {
        auto json = std::make_unique<juce::DynamicObject>();
        json->setProperty ("preset_name", name);

        if (auto* settingsObj = settings.getDynamicObject())
        {
            if (auto* algorithms = settingsObj->getProperty ("algorithms").getDynamicObject())
            {
                auto algoCopy = std::make_unique<juce::DynamicObject> (*algorithms);
                json->setProperty ("algorithms", juce::var (algoCopy.release()));
            }
        }

        auto jsonString = juce::JSON::toString (juce::var (json.release()));

        auto url = makeUrl ("/presets.json")
            .withPOSTData (jsonString);

        int statusCode = 0;
        auto options = juce::URL::InputStreamOptions (juce::URL::ParameterHandling::inPostData)
            .withExtraHeaders ("Authorization: Bearer " + token + "\r\nContent-Type: application/json")
            .withConnectionTimeoutMs (30000)
            .withStatusCode (&statusCode);

        juce::String response;
        if (auto stream = url.createInputStream (options))
            response = stream->readEntireStreamAsString();

        juce::String uuid, error;
        bool success = false;

        if (statusCode == 200 || statusCode == 201)
        {
            auto parsed = juce::JSON::parse (response);
            uuid = parsed.getProperty ("data", juce::var())
                         .getProperty ("uuid", "").toString();
            success = uuid.isNotEmpty();
            if (! success)
                error = "No UUID in response";
        }
        else
        {
            auto parsed = juce::JSON::parse (response);
            error = parsed.getProperty ("error_message", "HTTP " + juce::String (statusCode)).toString();
        }

        juce::MessageManager::callAsync ([callback, success, uuid, error] { callback (success, uuid, error); });
    });
}

void AuphonicApiClient::createProduction (const juce::String& presetUuid,
                                           const juce::var& manualSettings,
                                           const juce::String& title,
                                           ProductionCallback callback)
{
    juce::Thread::launch ([this, presetUuid, manualSettings, title, callback]
    {
        auto json = std::make_unique<juce::DynamicObject>();

        json->setProperty ("title", title);
        json->setProperty ("output_basename", title);

        auto metadata = std::make_unique<juce::DynamicObject>();
        metadata->setProperty ("title", title);
        json->setProperty ("metadata", juce::var (metadata.release()));

        if (presetUuid.isNotEmpty())
            json->setProperty ("preset", presetUuid);

        juce::String outputFormat;
        int outputBitrate = 0;
        if (auto* manualObj = manualSettings.getDynamicObject())
        {
            for (auto& prop : manualObj->getProperties())
            {
                if (prop.name.toString() == "output_format")
                    outputFormat = prop.value.toString();
                else if (prop.name.toString() == "output_bitrate")
                    outputBitrate = (int) prop.value;
                else
                    json->setProperty (prop.name, prop.value);
            }
        }

        if (outputFormat.isNotEmpty())
        {
            auto outputFileObj = std::make_unique<juce::DynamicObject>();
            outputFileObj->setProperty ("format", outputFormat);
            if (outputBitrate > 0)
                outputFileObj->setProperty ("bitrate", outputBitrate);
            juce::Array<juce::var> outputFiles;
            outputFiles.add (juce::var (outputFileObj.release()));
            json->setProperty ("output_files", outputFiles);
        }

        auto jsonString = juce::JSON::toString (juce::var (json.release()));

        auto url = makeUrl ("/productions.json")
            .withPOSTData (jsonString);

        int statusCode = 0;
        auto options = juce::URL::InputStreamOptions (juce::URL::ParameterHandling::inPostData)
            .withExtraHeaders ("Authorization: Bearer " + token + "\r\nContent-Type: application/json")
            .withConnectionTimeoutMs (30000)
            .withStatusCode (&statusCode);

        juce::String response;
        if (auto stream = url.createInputStream (options))
            response = stream->readEntireStreamAsString();

        juce::String uuid, error;
        bool success = false;

        if (statusCode == 200 || statusCode == 201)
        {
            auto parsed = juce::JSON::parse (response);
            uuid = parsed.getProperty ("data", juce::var())
                         .getProperty ("uuid", "").toString();
            success = uuid.isNotEmpty();
            if (! success)
                error = "No UUID in response";
        }
        else
        {
            auto parsed = juce::JSON::parse (response);
            error = parsed.getProperty ("error_message", "HTTP " + juce::String (statusCode)).toString();
        }

        juce::MessageManager::callAsync ([callback, success, uuid, error] { callback (success, uuid, error); });
    });
}

void AuphonicApiClient::uploadFile (const juce::String& productionUuid,
                                     const juce::File& file,
                                     UploadCallback callback)
{
    juce::Thread::launch ([this, productionUuid, file, callback]
    {
        auto url = makeUrl ("/production/" + productionUuid + "/upload.json")
            .withFileToUpload ("input_file", file, "audio/*");

        int statusCode = 0;
        auto options = juce::URL::InputStreamOptions (juce::URL::ParameterHandling::inPostData)
            .withExtraHeaders ("Authorization: Bearer " + token)
            .withConnectionTimeoutMs (300000)
            .withStatusCode (&statusCode);

        juce::String response;
        if (auto stream = url.createInputStream (options))
            response = stream->readEntireStreamAsString();

        bool success = (statusCode == 200 || statusCode == 201);
        juce::String error;
        if (! success)
        {
            auto parsed = juce::JSON::parse (response);
            error = parsed.getProperty ("error_message", "Upload failed (HTTP " + juce::String (statusCode) + ")").toString();
        }

        juce::MessageManager::callAsync ([callback, success, error] { callback (success, error); });
    });
}

void AuphonicApiClient::startProduction (const juce::String& productionUuid,
                                          StartCallback callback)
{
    juce::Thread::launch ([this, productionUuid, callback]
    {
        auto url = makeUrl ("/production/" + productionUuid + "/start.json");

        int statusCode = 0;
        auto response = performPost (url, statusCode);

        bool success = (statusCode == 200 || statusCode == 201);
        juce::String error;
        if (! success)
        {
            auto parsed = juce::JSON::parse (response);
            error = parsed.getProperty ("error_message", "Start failed (HTTP " + juce::String (statusCode) + ")").toString();
        }

        juce::MessageManager::callAsync ([callback, success, error] { callback (success, error); });
    });
}

void AuphonicApiClient::getProductionStatus (const juce::String& productionUuid,
                                              StatusCallback callback)
{
    juce::Thread::launch ([this, productionUuid, callback]
    {
        auto url = makeUrl ("/production/" + productionUuid + ".json");

        int statusCode = 0;
        auto response = performGet (url, statusCode);

        ProductionStatus status;
        status.uuid = productionUuid;
        bool success = false;

        if (statusCode == 200)
        {
            auto parsed = juce::JSON::parse (response);
            auto data = parsed.getProperty ("data", juce::var());

            status.statusCode = (int) data.getProperty ("status", 0);
            status.statusString = data.getProperty ("status_string", "").toString();
            status.progress = (double) data.getProperty ("progress", 0.0);
            status.errorMessage = data.getProperty ("error_message", "").toString();

            if (auto* outputs = data.getProperty ("output_files", {}).getArray())
            {
                if (outputs->size() > 0)
                    status.outputFileUrl = (*outputs)[0].getProperty ("download_url", "").toString();
            }

            success = true;
        }

        juce::MessageManager::callAsync ([callback, success, status] { callback (success, status); });
    });
}

void AuphonicApiClient::downloadFile (const juce::String& downloadUrl,
                                       DownloadCallback callback)
{
    auto tokenCopy = token;

    juce::Thread::launch ([callback, downloadUrl, tokenCopy]
    {
        juce::String ext = juce::URL (downloadUrl).getFileName().fromLastOccurrenceOf (".", false, false);
        if (ext.isEmpty()) ext = "wav";
        auto tempFile = juce::File::getSpecialLocation (juce::File::tempDirectory)
            .getChildFile ("auphonic_download_" + juce::String (juce::Random::getSystemRandom().nextInt64()) + "." + ext);

        auto url = juce::URL (downloadUrl);
        int statusCode = 0;
        auto options = juce::URL::InputStreamOptions (juce::URL::ParameterHandling::inAddress)
            .withExtraHeaders ("Authorization: Bearer " + tokenCopy)
            .withConnectionTimeoutMs (300000)
            .withStatusCode (&statusCode);

        bool success = false;
        juce::String error;

        if (auto stream = url.createInputStream (options))
        {
            juce::FileOutputStream output (tempFile);
            if (output.openedOk())
            {
                output.writeFromInputStream (*stream, -1);
                output.flush();
                success = (statusCode == 200 && tempFile.getSize() > 0);
                if (! success)
                    error = "Download failed or empty file";
            }
            else
            {
                error = "Could not create temp file";
            }
        }
        else
        {
            error = "Could not connect to download URL";
        }

        juce::MessageManager::callAsync ([callback, success, tempFile, error] { callback (success, tempFile, error); });
    });
}
