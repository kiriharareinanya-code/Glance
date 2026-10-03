// Ported from Lyricify.Lyrics.Helper/Providers/Web/MusixMatch/Response.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import '../../../json_utils.dart';

// ===== GetTokenResponse =====

class GetTokenResponse {
  GetTokenResponse({required this.message});

  factory GetTokenResponse.fromJson(Map<String, dynamic> j) => GetTokenResponse(
        message: j['message'] == null
            ? null
            : GetTokenMessageContent.fromJson(asObj(j['message'])),
      );

  GetTokenMessageContent? message;
}

class GetTokenMessageContent {
  GetTokenMessageContent({required this.header, required this.body});

  factory GetTokenMessageContent.fromJson(Map<String, dynamic> j) =>
      GetTokenMessageContent(
        header: j['header'] == null
            ? null
            : GetTokenHeader.fromJson(asObj(j['header'])),
        body: j['body'] == null ? null : GetTokenBody.fromJson(asObj(j['body'])),
      );

  GetTokenHeader? header;

  GetTokenBody? body;
}

class GetTokenHeader {
  GetTokenHeader({
    required this.statusCode,
    required this.executeTime,
    required this.pid,
    required this.surrogateKeyList,
    required this.hint,
  });

  factory GetTokenHeader.fromJson(Map<String, dynamic> j) => GetTokenHeader(
        statusCode: asIntOrNull(j['status_code']),
        executeTime: asDouble(j['execute_time']),
        pid: asIntOrNull(j['pid']),
        surrogateKeyList: j['surrogate_key_list'] is List
            ? List<Object?>.from(asArr(j['surrogate_key_list']))
            : null,
        hint: asStr(j['hint']),
      );

  int? statusCode;

  double executeTime;

  int? pid;

  List<Object?>? surrogateKeyList;

  String hint;
}

class GetTokenBody {
  GetTokenBody({required this.userToken, required this.appConfig, required this.location});

  factory GetTokenBody.fromJson(Map<String, dynamic> j) => GetTokenBody(
        userToken: j['user_token'] == null ? null : asStr(j['user_token']),
        appConfig: j['app_config'] == null
            ? null
            : GetTokenAppConfig.fromJson(asObj(j['app_config'])),
        location: j['location'] == null
            ? null
            : GetTokenLocation.fromJson(asObj(j['location'])),
      );

  String? userToken;

  GetTokenAppConfig? appConfig;

  GetTokenLocation? location;
}

class GetTokenAppConfig {
  GetTokenAppConfig({
    required this.trial,
    required this.mobilePopOverMaximum,
    required this.mobilePopOverMinTimes,
    required this.mobilePopOverMaxTimes,
    required this.isRoviCopyEnabled,
    required this.isGettyCopyEnabled,
    required this.searchMaxResults,
    required this.fbShareUrlSpotify,
    required this.twShareUrlSpotify,
    required this.fbPostTimeline,
    required this.fbOpenGraph,
    required this.subtitlesMaxDeviation,
    required this.localeDefaultLang,
    required this.missionEnable,
    required this.contentTeam,
    required this.missions,
    required this.missionManagerCategories,
    required this.appstoreProducts,
    required this.trackingList,
    required this.spotifyCountries,
    required this.serviceList,
    required this.showAmazonMusic,
    required this.isSentryEnabled,
    required this.languages,
    required this.lastUpdated,
    required this.cluster,
    required this.eventMap,
    required this.missionReportTypes,
    required this.canShowPerformersTag,
    required this.smartTranslations,
    required this.audioUpload,
  });

  factory GetTokenAppConfig.fromJson(Map<String, dynamic> j) => GetTokenAppConfig(
        trial: asBool(j['trial']),
        mobilePopOverMaximum: asInt(j['mobilePopOverMaximum']),
        mobilePopOverMinTimes: asInt(j['mobilePopOverMinTimes']),
        mobilePopOverMaxTimes: asInt(j['mobilePopOverMaxTimes']),
        isRoviCopyEnabled: asBool(j['isRoviCopyEnabled']),
        isGettyCopyEnabled: asBool(j['isGettyCopyEnabled']),
        searchMaxResults: asInt(j['searchMaxResults']),
        fbShareUrlSpotify: asBool(j['fbShareUrlSpotify']),
        twShareUrlSpotify: asBool(j['twShareUrlSpotify']),
        fbPostTimeline: asBool(j['fbPostTimeline']),
        fbOpenGraph: asBool(j['fbOpenGraph']),
        subtitlesMaxDeviation: asInt(j['subtitlesMaxDeviation']),
        localeDefaultLang: asStr(j['localeDefaultLang']),
        missionEnable: asBool(j['missionEnable']),
        contentTeam: asBool(j['content_team']),
        missions: j['missions'] == null
            ? null
            : GetTokenMissions.fromJson(asObj(j['missions'])),
        missionManagerCategories: j['mission_manager_categories'] == null
            ? null
            : GetTokenMissionManagerCategories.fromJson(
                asObj(j['mission_manager_categories'])),
        appstoreProducts: j['appstore_products'] is List
            ? List<Object?>.from(asArr(j['appstore_products']))
            : null,
        trackingList: j['tracking_list'] is List
            ? [
                for (final e in asArr(j['tracking_list']))
                  GetTokenTrackingList.fromJson(asObj(e))
              ]
            : null,
        spotifyCountries: j['spotifyCountries'] is List
            ? [for (final e in asArr(j['spotifyCountries'])) asStr(e)]
            : null,
        serviceList: j['service_list'] is List
            ? [
                for (final e in asArr(j['service_list']))
                  GetTokenServiceList.fromJson(asObj(e))
              ]
            : null,
        showAmazonMusic: asBool(j['show_amazon_music']),
        isSentryEnabled: asBool(j['isSentryEnabled']),
        languages: j['languages'] is List
            ? [for (final e in asArr(j['languages'])) asStr(e)]
            : null,
        lastUpdated: asStr(j['last_updated']),
        cluster: asStr(j['cluster']),
        eventMap: j['event_map'] is List
            ? [for (final e in asArr(j['event_map'])) GetTokenEventMap.fromJson(asObj(e))]
            : null,
        missionReportTypes: j['mission_report_types'] is List
            ? [for (final e in asArr(j['mission_report_types'])) asStr(e)]
            : null,
        canShowPerformersTag: asBool(j['can_show_performers_tag']),
        smartTranslations: j['smart_translations'] == null
            ? null
            : GetTokenSmartTranslations.fromJson(asObj(j['smart_translations'])),
        audioUpload: asBool(j['audio_upload']),
      );

  bool trial;

  int mobilePopOverMaximum;

  int mobilePopOverMinTimes;

  int mobilePopOverMaxTimes;

  bool isRoviCopyEnabled;

  bool isGettyCopyEnabled;

  int searchMaxResults;

  bool fbShareUrlSpotify;

  bool twShareUrlSpotify;

  bool fbPostTimeline;

  bool fbOpenGraph;

  int subtitlesMaxDeviation;

  String localeDefaultLang;

  bool missionEnable;

  bool contentTeam;

  GetTokenMissions? missions;

  GetTokenMissionManagerCategories? missionManagerCategories;

  List<Object?>? appstoreProducts;

  List<GetTokenTrackingList>? trackingList;

  List<String>? spotifyCountries;

  List<GetTokenServiceList>? serviceList;

  bool showAmazonMusic;

  bool isSentryEnabled;

  List<String>? languages;

  String lastUpdated;

  String cluster;

  List<GetTokenEventMap>? eventMap;

  List<String>? missionReportTypes;

  bool canShowPerformersTag;

  GetTokenSmartTranslations? smartTranslations;

  bool audioUpload;
}

class GetTokenMissions {
  GetTokenMissions({required this.enabled, required this.community});

  factory GetTokenMissions.fromJson(Map<String, dynamic> j) => GetTokenMissions(
        enabled: asBool(j['enabled']),
        community: j['community'] is List
            ? [for (final e in asArr(j['community'])) asStr(e)]
            : null,
      );

  bool enabled;

  List<String>? community;
}

class GetTokenMissionManagerCategories {
  GetTokenMissionManagerCategories({
    required this.taskTypes,
    required this.audioSources,
    required this.userGroups,
    required this.rewards,
  });

  factory GetTokenMissionManagerCategories.fromJson(Map<String, dynamic> j) =>
      GetTokenMissionManagerCategories(
        taskTypes: j['taskTypes'] is List
            ? [for (final e in asArr(j['taskTypes'])) GetTokenTaskType.fromJson(asObj(e))]
            : null,
        audioSources: j['audioSources'] is List
            ? [
                for (final e in asArr(j['audioSources']))
                  GetTokenAudioSource.fromJson(asObj(e))
              ]
            : null,
        userGroups: j['userGroups'] is List
            ? [for (final e in asArr(j['userGroups'])) GetTokenUserGroup.fromJson(asObj(e))]
            : null,
        rewards: j['rewards'] is List
            ? [for (final e in asArr(j['rewards'])) GetTokenReward.fromJson(asObj(e))]
            : null,
      );

  List<GetTokenTaskType>? taskTypes;

  List<GetTokenAudioSource>? audioSources;

  List<GetTokenUserGroup>? userGroups;

  List<GetTokenReward>? rewards;
}

class GetTokenTaskType {
  GetTokenTaskType({required this.value, required this.label});

  factory GetTokenTaskType.fromJson(Map<String, dynamic> j) => GetTokenTaskType(
        value: asStr(j['value']),
        label: asStr(j['label']),
      );

  String value;

  String label;
}

class GetTokenAudioSource {
  GetTokenAudioSource({required this.value, required this.label});

  factory GetTokenAudioSource.fromJson(Map<String, dynamic> j) =>
      GetTokenAudioSource(
        value: asStr(j['value']),
        label: asStr(j['label']),
      );

  String value;

  String label;
}

class GetTokenUserGroup {
  GetTokenUserGroup({required this.value, required this.label});

  factory GetTokenUserGroup.fromJson(Map<String, dynamic> j) => GetTokenUserGroup(
        value: asStr(j['value']),
        label: asStr(j['label']),
      );

  String value;

  String label;
}

class GetTokenReward {
  GetTokenReward({required this.label, required this.value});

  factory GetTokenReward.fromJson(Map<String, dynamic> j) => GetTokenReward(
        label: asStr(j['label']),
        value: asStr(j['value']),
      );

  String label;

  String value;
}

class GetTokenTrackingList {
  GetTokenTrackingList({required this.tracking});

  factory GetTokenTrackingList.fromJson(Map<String, dynamic> j) =>
      GetTokenTrackingList(
        tracking: j['tracking'] == null
            ? null
            : GetTokenTracking.fromJson(asObj(j['tracking'])),
      );

  GetTokenTracking? tracking;
}

class GetTokenTracking {
  GetTokenTracking({required this.context, required this.delay, required this.trackCacheTtl});

  factory GetTokenTracking.fromJson(Map<String, dynamic> j) => GetTokenTracking(
        context: asStr(j['context']),
        delay: asInt(j['delay']),
        trackCacheTtl: asInt(j['track_cache_ttl']),
      );

  String context;

  int delay;

  int trackCacheTtl;
}

class GetTokenServiceList {
  GetTokenServiceList({required this.service});

  factory GetTokenServiceList.fromJson(Map<String, dynamic> j) =>
      GetTokenServiceList(
        service: j['service'] == null
            ? null
            : GetTokenService.fromJson(asObj(j['service'])),
      );

  GetTokenService? service;
}

class GetTokenService {
  GetTokenService({
    required this.name,
    required this.displayName,
    required this.type,
    required this.oauthApi,
    required this.oauthWebSignin,
    required this.streaming,
    required this.playlist,
    required this.locker,
    required this.deeplink,
  });

  factory GetTokenService.fromJson(Map<String, dynamic> j) => GetTokenService(
        name: asStr(j['name']),
        displayName: asStr(j['display_name']),
        type: asStr(j['type']),
        oauthApi: asBool(j['oauth_api']),
        oauthWebSignin: j['oauth_web_signin'] == null
            ? null
            : GetTokenOauthWebSignin.fromJson(asObj(j['oauth_web_signin'])),
        streaming: asBool(j['streaming']),
        playlist: asBool(j['playlist']),
        locker: asBool(j['locker']),
        deeplink: asBool(j['deeplink']),
      );

  String name;

  String displayName;

  String type;

  bool oauthApi;

  GetTokenOauthWebSignin? oauthWebSignin;

  bool streaming;

  bool playlist;

  bool locker;

  bool deeplink;
}

class GetTokenOauthWebSignin {
  GetTokenOauthWebSignin({required this.enabled, required this.userPrefix});

  factory GetTokenOauthWebSignin.fromJson(Map<String, dynamic> j) =>
      GetTokenOauthWebSignin(
        enabled: asBool(j['enabled']),
        userPrefix: asStr(j['user_prefix']),
      );

  bool enabled;

  String userPrefix;
}

class GetTokenEventMap {
  GetTokenEventMap({required this.regex, required this.enabled, required this.piggyback});

  factory GetTokenEventMap.fromJson(Map<String, dynamic> j) => GetTokenEventMap(
        regex: asStr(j['regex']),
        enabled: asBool(j['enabled']),
        piggyback: j['piggyback'] == null
            ? null
            : GetTokenPiggyback.fromJson(asObj(j['piggyback'])),
      );

  String regex;

  bool enabled;

  GetTokenPiggyback? piggyback;
}

class GetTokenPiggyback {
  GetTokenPiggyback({required this.serverWeight});

  factory GetTokenPiggyback.fromJson(Map<String, dynamic> j) =>
      GetTokenPiggyback(serverWeight: asInt(j['server_weight']));

  int serverWeight;
}

class GetTokenSmartTranslations {
  GetTokenSmartTranslations({required this.enabled, required this.threshold});

  factory GetTokenSmartTranslations.fromJson(Map<String, dynamic> j) =>
      GetTokenSmartTranslations(
        enabled: asBool(j['enabled']),
        threshold: asInt(j['threshold']),
      );

  bool enabled;

  int threshold;
}

class GetTokenLocation {
  GetTokenLocation({
    required this.geoIPCityCountryCode,
    required this.geoIPCityCountryCode3,
    required this.geoIPCityCountryName,
    required this.geoIPCity,
    required this.geoIPCityContinentCode,
    required this.geoIPLatitude,
    required this.geoIPLongitude,
    required this.geoIPAsOrg,
    required this.geoIPOrg,
    required this.geoIPIsp,
    required this.geoIPNetName,
    required this.badipTags,
  });

  factory GetTokenLocation.fromJson(Map<String, dynamic> j) => GetTokenLocation(
        geoIPCityCountryCode: asStr(j['GEOIP_CITY_COUNTRY_CODE']),
        geoIPCityCountryCode3: asStr(j['GEOIP_CITY_COUNTRY_CODE3']),
        geoIPCityCountryName: asStr(j['GEOIP_CITY_COUNTRY_NAME']),
        geoIPCity: asStr(j['GEOIP_CITY']),
        geoIPCityContinentCode: asStr(j['GEOIP_CITY_CONTINENT_CODE']),
        geoIPLatitude: asDouble(j['GEOIP_LATITUDE']),
        geoIPLongitude: asDouble(j['GEOIP_LONGITUDE']),
        geoIPAsOrg: asStr(j['GEOIP_AS_ORG']),
        geoIPOrg: asStr(j['GEOIP_ORG']),
        geoIPIsp: asStr(j['GEOIP_ISP']),
        geoIPNetName: asStr(j['GEOIP_NET_NAME']),
        badipTags: j['BADIP_TAGS'] is List
            ? List<Object?>.from(asArr(j['BADIP_TAGS']))
            : null,
      );

  String geoIPCityCountryCode;

  String geoIPCityCountryCode3;

  String geoIPCityCountryName;

  String geoIPCity;

  String geoIPCityContinentCode;

  double geoIPLatitude;

  double geoIPLongitude;

  String geoIPAsOrg;

  String geoIPOrg;

  String geoIPIsp;

  String geoIPNetName;

  List<Object?>? badipTags;
}

// ===== GetTrackResponse =====

class GetTrackResponse {
  GetTrackResponse({required this.message});

  factory GetTrackResponse.fromJson(Map<String, dynamic> j) => GetTrackResponse(
        message: j['message'] == null
            ? null
            : GetTrackMessageContent.fromJson(asObj(j['message'])),
      );

  GetTrackMessageContent? message;
}

class GetTrackMessageContent {
  GetTrackMessageContent({required this.header, required this.body});

  factory GetTrackMessageContent.fromJson(Map<String, dynamic> j) =>
      GetTrackMessageContent(
        header: j['header'] == null
            ? null
            : GetTrackHeader.fromJson(asObj(j['header'])),
        body: j['body'] == null ? null : GetTrackBody.fromJson(asObj(j['body'])),
      );

  GetTrackHeader? header;

  GetTrackBody? body;
}

class GetTrackHeader {
  GetTrackHeader({
    required this.statusCode,
    required this.executeTime,
    required this.confidence,
    required this.mode,
    required this.cached,
    required this.hint,
  });

  factory GetTrackHeader.fromJson(Map<String, dynamic> j) => GetTrackHeader(
        statusCode: asIntOrNull(j['status_code']),
        executeTime: asDouble(j['execute_time']),
        confidence: asInt(j['confidence']),
        mode: asStr(j['mode']),
        cached: asInt(j['cached']),
        hint: asStr(j['hint']),
      );

  int? statusCode;

  double executeTime;

  int confidence;

  String mode;

  int cached;

  String hint;
}

class GetTrackBody {
  GetTrackBody({required this.track});

  factory GetTrackBody.fromJson(Map<String, dynamic> j) => GetTrackBody(
        track: j['track'] == null
            ? null
            : GetTrackTrack.fromJson(asObj(j['track'])),
      );

  GetTrackTrack? track;
}

class GetTrackTrack {
  GetTrackTrack({
    required this.trackId,
    required this.trackMbid,
    required this.trackIsrc,
    required this.commontrackIsrcs,
    required this.trackSpotifyId,
    required this.commontrackSpotifyIds,
    required this.trackSoundcloudId,
    required this.trackXboxmusicId,
    required this.trackName,
    required this.trackNameTranslationList,
    required this.trackRating,
    required this.trackLength,
    required this.commontrackId,
    required this.instrumental,
    required this.explicit,
    required this.hasLyrics,
    required this.hasLyricsCrowd,
    required this.hasSubtitles,
    required this.hasRichsync,
    required this.hasTrackStructure,
    required this.numFavourite,
    required this.lyricsId,
    required this.subtitleId,
    required this.albumId,
    required this.albumName,
    required this.albumVanityId,
    required this.artistId,
    required this.artistMbid,
    required this.artistName,
    required this.albumCoverart100x100,
    required this.albumCoverart350x350,
    required this.albumCoverart500x500,
    required this.albumCoverart800x800,
    required this.trackShareUrl,
    required this.trackEditUrl,
    required this.commontrackVanityId,
    required this.restricted,
    required this.firstReleaseDate,
    required this.updatedTime,
    required this.primaryGenres,
    required this.secondaryGenres,
  });

  factory GetTrackTrack.fromJson(Map<String, dynamic> j) => GetTrackTrack(
        trackId: asInt(j['track_id']),
        trackMbid: asStr(j['track_mbid']),
        trackIsrc: asStr(j['track_isrc']),
        commontrackIsrcs: j['commontrack_isrcs'] is List
            ? [
                for (final e in asArr(j['commontrack_isrcs']))
                  [for (final inner in asArr(e)) asStr(inner)]
              ]
            : null,
        trackSpotifyId: asStr(j['track_spotify_id']),
        commontrackSpotifyIds: j['commontrack_spotify_ids'] is List
            ? [for (final e in asArr(j['commontrack_spotify_ids'])) asStr(e)]
            : null,
        trackSoundcloudId: asInt(j['track_soundcloud_id']),
        trackXboxmusicId: asStr(j['track_xboxmusic_id']),
        trackName: asStr(j['track_name']),
        trackNameTranslationList: j['track_name_translation_list'] is List
            ? [
                for (final e in asArr(j['track_name_translation_list']))
                  GetTrackTrackNameTranslationList.fromJson(asObj(e))
              ]
            : null,
        trackRating: asInt(j['track_rating']),
        trackLength: asInt(j['track_length']),
        commontrackId: asInt(j['commontrack_id']),
        instrumental: asInt(j['instrumental']),
        explicit: asInt(j['explicit']),
        hasLyrics: asInt(j['has_lyrics']),
        hasLyricsCrowd: asInt(j['has_lyrics_crowd']),
        hasSubtitles: asInt(j['has_subtitles']),
        hasRichsync: asInt(j['has_richsync']),
        hasTrackStructure: asInt(j['has_track_structure']),
        numFavourite: asInt(j['num_favourite']),
        lyricsId: asInt(j['lyrics_id']),
        subtitleId: asInt(j['subtitle_id']),
        albumId: asInt(j['album_id']),
        albumName: asStr(j['album_name']),
        albumVanityId: asStr(j['album_vanity_id']),
        artistId: asInt(j['artist_id']),
        artistMbid: asStr(j['artist_mbid']),
        artistName: asStr(j['artist_name']),
        albumCoverart100x100: asStr(j['album_coverart_100x100']),
        albumCoverart350x350: asStr(j['album_coverart_350x350']),
        albumCoverart500x500: asStr(j['album_coverart_500x500']),
        albumCoverart800x800: asStr(j['album_coverart_800x800']),
        trackShareUrl: asStr(j['track_share_url']),
        trackEditUrl: asStr(j['track_edit_url']),
        commontrackVanityId: asStr(j['commontrack_vanity_id']),
        restricted: asInt(j['restricted']),
        firstReleaseDate: j['first_release_date'] == null
            ? null
            : asStr(j['first_release_date']),
        updatedTime: asStr(j['updated_time']),
        primaryGenres: j['primary_genres'] == null
            ? null
            : GetTrackPrimaryGenres.fromJson(asObj(j['primary_genres'])),
        secondaryGenres: j['secondary_genres'] == null
            ? null
            : GetTrackSecondaryGenres.fromJson(asObj(j['secondary_genres'])),
      );

  int trackId;

  String trackMbid;

  String trackIsrc;

  List<List<String>>? commontrackIsrcs;

  String trackSpotifyId;

  List<String>? commontrackSpotifyIds;

  int trackSoundcloudId;

  String trackXboxmusicId;

  String trackName;

  List<GetTrackTrackNameTranslationList>? trackNameTranslationList;

  int trackRating;

  int trackLength;

  int commontrackId;

  int instrumental;

  int explicit;

  int hasLyrics;

  int hasLyricsCrowd;

  int hasSubtitles;

  int hasRichsync;

  int hasTrackStructure;

  int numFavourite;

  int lyricsId;

  int subtitleId;

  int albumId;

  String albumName;

  String albumVanityId;

  int artistId;

  String artistMbid;

  String artistName;

  String albumCoverart100x100;

  String albumCoverart350x350;

  String albumCoverart500x500;

  String albumCoverart800x800;

  String trackShareUrl;

  String trackEditUrl;

  String commontrackVanityId;

  int restricted;

  String? firstReleaseDate;

  String updatedTime;

  GetTrackPrimaryGenres? primaryGenres;

  GetTrackSecondaryGenres? secondaryGenres;
}

class GetTrackTrackNameTranslationList {
  GetTrackTrackNameTranslationList({required this.trackNameTranslation});

  factory GetTrackTrackNameTranslationList.fromJson(Map<String, dynamic> j) =>
      GetTrackTrackNameTranslationList(
        trackNameTranslation: j['track_name_translation'] == null
            ? null
            : GetTrackTrackNameTranslation.fromJson(
                asObj(j['track_name_translation'])),
      );

  GetTrackTrackNameTranslation? trackNameTranslation;
}

class GetTrackTrackNameTranslation {
  GetTrackTrackNameTranslation({required this.language, required this.translation});

  factory GetTrackTrackNameTranslation.fromJson(Map<String, dynamic> j) =>
      GetTrackTrackNameTranslation(
        language: asStr(j['language']),
        translation: asStr(j['translation']),
      );

  String language;

  String translation;
}

class GetTrackPrimaryGenres {
  GetTrackPrimaryGenres({required this.musicGenreList});

  factory GetTrackPrimaryGenres.fromJson(Map<String, dynamic> j) =>
      GetTrackPrimaryGenres(
        musicGenreList: j['music_genre_list'] is List
            ? [
                for (final e in asArr(j['music_genre_list']))
                  GetTrackMusicGenreList.fromJson(asObj(e))
              ]
            : null,
      );

  List<GetTrackMusicGenreList>? musicGenreList;
}

class GetTrackMusicGenreList {
  GetTrackMusicGenreList({required this.musicGenre});

  factory GetTrackMusicGenreList.fromJson(Map<String, dynamic> j) =>
      GetTrackMusicGenreList(
        musicGenre: j['music_genre'] == null
            ? null
            : GetTrackMusicGenre.fromJson(asObj(j['music_genre'])),
      );

  GetTrackMusicGenre? musicGenre;
}

class GetTrackMusicGenre {
  GetTrackMusicGenre({
    required this.musicGenreId,
    required this.musicGenreParentId,
    required this.musicGenreName,
    required this.musicGenreNameExtended,
    required this.musicGenreVanity,
  });

  factory GetTrackMusicGenre.fromJson(Map<String, dynamic> j) =>
      GetTrackMusicGenre(
        musicGenreId: asInt(j['music_genre_id']),
        musicGenreParentId: asInt(j['music_genre_parent_id']),
        musicGenreName: asStr(j['music_genre_name']),
        musicGenreNameExtended: asStr(j['music_genre_name_extended']),
        musicGenreVanity: asStr(j['music_genre_vanity']),
      );

  int musicGenreId;

  int musicGenreParentId;

  String musicGenreName;

  String musicGenreNameExtended;

  String musicGenreVanity;
}

class GetTrackSecondaryGenres {
  GetTrackSecondaryGenres({required this.musicGenreList});

  factory GetTrackSecondaryGenres.fromJson(Map<String, dynamic> j) =>
      GetTrackSecondaryGenres(
        musicGenreList: j['music_genre_list'] is List
            ? [
                for (final e in asArr(j['music_genre_list']))
                  GetTrackMusicGenreList.fromJson(asObj(e))
              ]
            : null,
      );

  List<GetTrackMusicGenreList>? musicGenreList;
}

// ===== GetTranslationsResponse =====

class GetTranslationsResponse {
  GetTranslationsResponse({required this.message});

  factory GetTranslationsResponse.fromJson(Map<String, dynamic> j) =>
      GetTranslationsResponse(
        message: j['message'] == null
            ? null
            : GetTranslationsMessageContent.fromJson(asObj(j['message'])),
      );

  GetTranslationsMessageContent? message;
}

class GetTranslationsMessageContent {
  GetTranslationsMessageContent({required this.header, required this.body});

  factory GetTranslationsMessageContent.fromJson(Map<String, dynamic> j) =>
      GetTranslationsMessageContent(
        header: j['header'] == null
            ? null
            : GetTranslationsHeader.fromJson(asObj(j['header'])),
        body: j['body'] == null
            ? null
            : GetTranslationsBody.fromJson(asObj(j['body'])),
      );

  GetTranslationsHeader? header;

  GetTranslationsBody? body;
}

class GetTranslationsHeader {
  GetTranslationsHeader({required this.statusCode, required this.executeTime, required this.hint});

  factory GetTranslationsHeader.fromJson(Map<String, dynamic> j) =>
      GetTranslationsHeader(
        statusCode: asIntOrNull(j['status_code']),
        executeTime: asDouble(j['execute_time']),
        hint: asStr(j['hint']),
      );

  int? statusCode;

  double executeTime;

  String hint;
}

class GetTranslationsBody {
  GetTranslationsBody({required this.translationsList});

  factory GetTranslationsBody.fromJson(Map<String, dynamic> j) =>
      GetTranslationsBody(
        translationsList: j['translations_list'] is List
            ? [
                for (final e in asArr(j['translations_list']))
                  GetTranslationsTranslationsListItem.fromJson(asObj(e))
              ]
            : null,
      );

  List<GetTranslationsTranslationsListItem>? translationsList;
}

class GetTranslationsTranslationsListItem {
  GetTranslationsTranslationsListItem({required this.translation});

  factory GetTranslationsTranslationsListItem.fromJson(
          Map<String, dynamic> j) =>
      GetTranslationsTranslationsListItem(
        translation: j['translation'] == null
            ? null
            : GetTranslationsTranslation.fromJson(asObj(j['translation'])),
      );

  GetTranslationsTranslation? translation;
}

class GetTranslationsTranslation {
  GetTranslationsTranslation({
    required this.typeId,
    required this.artistId,
    required this.languageFrom,
    required this.userId,
    required this.appId,
    required this.description,
    required this.snippet,
    required this.position,
    required this.selectedLanguage,
    required this.index,
    required this.wantkey,
    required this.createTimestamp,
    required this.language,
    required this.typeIdWeight,
    required this.lastUpdated,
    required this.key,
    required this.matchedLine,
    required this.subtitleMatchedLine,
    required this.confidence,
    required this.userScore,
    required this.publishedStatusMacro,
    required this.imageId,
    required this.videoId,
    required this.lyricsId,
    required this.subtitleId,
    required this.createdDate,
    required this.commontrackId,
    required this.isExpired,
    required this.groupKey,
    required this.canDelete,
    required this.isMine,
    required this.canApprove,
    required this.user,
    required this.approver,
    required this.canTranslate,
  });

  factory GetTranslationsTranslation.fromJson(Map<String, dynamic> j) =>
      GetTranslationsTranslation(
        typeId: asStr(j['type_id']),
        artistId: asInt(j['artist_id']),
        languageFrom: asStr(j['language_from']),
        userId: asStr(j['user_id']),
        appId: asStr(j['app_id']),
        description: asStr(j['description']),
        snippet: asStr(j['snippet']),
        position: asInt(j['position']),
        selectedLanguage: asStr(j['selected_language']),
        index: asInt(j['index']),
        wantkey: asBool(j['wantkey']),
        createTimestamp: asInt(j['create_timestamp']),
        language: asStr(j['language']),
        typeIdWeight: asInt(j['type_id_weight']),
        lastUpdated: asStr(j['last_updated']),
        key: asStr(j['key']),
        matchedLine: asStr(j['matched_line']),
        subtitleMatchedLine: asStr(j['subtitle_matched_line']),
        confidence: asDouble(j['confidence']),
        userScore: asInt(j['user_score']),
        publishedStatusMacro: j['published_status_macro'],
        imageId: asInt(j['image_id']),
        videoId: asInt(j['video_id']),
        lyricsId: asInt(j['lyrics_id']),
        subtitleId: asInt(j['subtitle_id']),
        createdDate: asStr(j['created_date']),
        commontrackId: asInt(j['commontrack_id']),
        isExpired: asInt(j['is_expired']),
        groupKey: asStr(j['group_key']),
        canDelete: asInt(j['can_delete']),
        isMine: asInt(j['is_mine']),
        canApprove: asInt(j['can_approve']),
        user: j['user'] == null
            ? null
            : GetTranslationsUser.fromJson(asObj(j['user'])),
        approver: j['approver'],
        canTranslate: asInt(j['can_translate']),
      );

  String typeId;

  int artistId;

  String languageFrom;

  String userId;

  String appId;

  String description;

  String snippet;

  int position;

  String selectedLanguage;

  int index;

  bool wantkey;

  int createTimestamp;

  String language;

  int typeIdWeight;

  String lastUpdated;

  String key;

  String matchedLine;

  String subtitleMatchedLine;

  double confidence;

  int userScore;

  Object? publishedStatusMacro;

  int imageId;

  int videoId;

  int lyricsId;

  int subtitleId;

  String createdDate;

  int commontrackId;

  int isExpired;

  String groupKey;

  int canDelete;

  int isMine;

  int canApprove;

  GetTranslationsUser? user;

  Object? approver;

  int canTranslate;
}

class GetTranslationsUser {
  GetTranslationsUser({
    required this.uaid,
    required this.isMine,
    required this.userName,
    required this.userProfilePhoto,
    required this.hasPrivateProfile,
    required this.hasInformativeProfilePage,
    required this.hasDistributorProfilePage,
    required this.score,
    required this.position,
    required this.level,
    required this.key,
    required this.rankLevel,
    required this.rankName,
    required this.rankColor,
    required this.rankColors,
    required this.rankImageUrl,
    required this.weeklyScore,
    required this.pointsToNextLevel,
    required this.ratioToNextLevel,
    required this.nextRankName,
    required this.ratioToNextRank,
    required this.nextRankColor,
    required this.nextRankColors,
    required this.nextRankImageUrl,
    required this.counters,
    required this.moderatorEligible,
    required this.artistManager,
    required this.academyCompleted,
    required this.academyCompletedDate,
  });

  factory GetTranslationsUser.fromJson(Map<String, dynamic> j) =>
      GetTranslationsUser(
        uaid: asStr(j['uaid']),
        isMine: asInt(j['is_mine']),
        userName: asStr(j['user_name']),
        userProfilePhoto: asStr(j['user_profile_photo']),
        hasPrivateProfile: asInt(j['has_private_profile']),
        hasInformativeProfilePage: asInt(j['has_informative_profile_page']),
        hasDistributorProfilePage: asInt(j['has_distributor_profile_page']),
        score: asInt(j['score']),
        position: asInt(j['position']),
        level: asStr(j['level']),
        key: asStr(j['key']),
        rankLevel: asInt(j['rank_level']),
        rankName: asStr(j['rank_name']),
        rankColor: asStr(j['rank_color']),
        rankColors: j['rank_colors'] == null
            ? null
            : GetTranslationsRankColors.fromJson(asObj(j['rank_colors'])),
        rankImageUrl: asStr(j['rank_image_url']),
        weeklyScore: asInt(j['weekly_score']),
        pointsToNextLevel: asInt(j['points_to_next_level']),
        ratioToNextLevel: asDouble(j['ratio_to_next_level']),
        nextRankName: asStr(j['next_rank_name']),
        ratioToNextRank: asDouble(j['ratio_to_next_rank']),
        nextRankColor: asStr(j['next_rank_color']),
        nextRankColors: j['next_rank_colors'] == null
            ? null
            : GetTranslationsRankColors.fromJson(asObj(j['next_rank_colors'])),
        nextRankImageUrl: asStr(j['next_rank_image_url']),
        counters: j['counters'] == null
            ? null
            : GetTranslationsCounters.fromJson(asObj(j['counters'])),
        moderatorEligible: asBool(j['moderator_eligible']),
        artistManager: asInt(j['artist_manager']),
        academyCompleted: asBool(j['academy_completed']),
        academyCompletedDate: asStr(j['academy_completed_date']),
      );

  String uaid;

  int isMine;

  String userName;

  String userProfilePhoto;

  int hasPrivateProfile;

  int hasInformativeProfilePage;

  int hasDistributorProfilePage;

  int score;

  int position;

  String level;

  String key;

  int rankLevel;

  String rankName;

  String rankColor;

  GetTranslationsRankColors? rankColors;

  String rankImageUrl;

  int weeklyScore;

  int pointsToNextLevel;

  double ratioToNextLevel;

  String nextRankName;

  double ratioToNextRank;

  String nextRankColor;

  GetTranslationsRankColors? nextRankColors;

  String nextRankImageUrl;

  GetTranslationsCounters? counters;

  bool moderatorEligible;

  int artistManager;

  bool academyCompleted;

  String academyCompletedDate;
}

class GetTranslationsRankColors {
  GetTranslationsRankColors({
    required this.rankColor10,
    required this.rankColor50,
    required this.rankColor100,
    required this.rankColor200,
  });

  factory GetTranslationsRankColors.fromJson(Map<String, dynamic> j) =>
      GetTranslationsRankColors(
        rankColor10: asStr(j['rank_color_10']),
        rankColor50: asStr(j['rank_color_50']),
        rankColor100: asStr(j['rank_color_100']),
        rankColor200: asStr(j['rank_color_200']),
      );

  String rankColor10;

  String rankColor50;

  String rankColor100;

  String rankColor200;
}

class GetTranslationsCounters {
  GetTranslationsCounters({
    required this.lyricsFavouriteAdded,
    required this.lyricsSubtitleAdded,
    required this.lyricsGenericKo,
    required this.lyricsMissing,
    required this.lyricsChanged,
    required this.lyricsOk,
    required this.lyricsToAdd,
    required this.lyricsKo,
    required this.lyricsMusicId,
    required this.voteBonuses,
    required this.trackTranslation,
    required this.voteMaluses,
    required this.lyricsAiIncorrectTextNo,
    required this.lyricsAiCompletelyWrongSkip,
    required this.lyricsAiIncorrectTextYes,
    required this.lyricsAiPhrasesNotRelatedYes,
    required this.lyricsImplicitlyOk,
    required this.lyricsReportCompletelyWrong,
    required this.lyricsRichsyncAdded,
    required this.trackInfluencerBonusModeratorVote,
    required this.lyricsAiMoodAnalysisV3Value,
    required this.lyricsAiUgcLanguage,
    required this.lyricsRankingChange,
    required this.trackStructure,
    required this.trackCompleteMetadata,
    required this.evaluationAcademyTest,
    required this.lyricsReportContainMistakes,
  });

  factory GetTranslationsCounters.fromJson(Map<String, dynamic> j) =>
      GetTranslationsCounters(
        lyricsFavouriteAdded: asInt(j['lyrics_favourite_added']),
        lyricsSubtitleAdded: asInt(j['lyrics_subtitle_added']),
        lyricsGenericKo: asInt(j['lyrics_generic_ko']),
        lyricsMissing: asInt(j['lyrics_missing']),
        lyricsChanged: asInt(j['lyrics_changed']),
        lyricsOk: asInt(j['lyrics_ok']),
        lyricsToAdd: asInt(j['lyrics_to_add']),
        lyricsKo: asInt(j['lyrics_ko']),
        lyricsMusicId: asInt(j['lyrics_music_id']),
        voteBonuses: asInt(j['vote_bonuses']),
        trackTranslation: asInt(j['track_translation']),
        voteMaluses: asInt(j['vote_maluses']),
        lyricsAiIncorrectTextNo: asInt(j['lyrics_ai_incorrect_text_no']),
        lyricsAiCompletelyWrongSkip:
            asInt(j['lyrics_ai_completely_wrong_skip']),
        lyricsAiIncorrectTextYes: asInt(j['lyrics_ai_incorrect_text_yes']),
        lyricsAiPhrasesNotRelatedYes:
            asInt(j['lyrics_ai_phrases_not_related_yes']),
        lyricsImplicitlyOk: asInt(j['lyrics_implicitly_ok']),
        lyricsReportCompletelyWrong:
            asInt(j['lyrics_report_completely_wrong']),
        lyricsRichsyncAdded: asInt(j['lyrics_richsync_added']),
        trackInfluencerBonusModeratorVote:
            asInt(j['track_influencer_bonus_moderator_vote']),
        lyricsAiMoodAnalysisV3Value:
            asInt(j['lyrics_ai_mood_analysis_v3_value']),
        lyricsAiUgcLanguage: asInt(j['lyrics_ai_ugc_language']),
        lyricsRankingChange: asInt(j['lyrics_ranking_change']),
        trackStructure: asInt(j['track_structure']),
        trackCompleteMetadata: asInt(j['track_complete_metadata']),
        evaluationAcademyTest: asInt(j['evaluation_academy_test']),
        lyricsReportContainMistakes:
            asInt(j['lyrics_report_contain_mistakes']),
      );

  int lyricsFavouriteAdded;

  int lyricsSubtitleAdded;

  int lyricsGenericKo;

  int lyricsMissing;

  int lyricsChanged;

  int lyricsOk;

  int lyricsToAdd;

  int lyricsKo;

  int lyricsMusicId;

  int voteBonuses;

  int trackTranslation;

  int voteMaluses;

  int lyricsAiIncorrectTextNo;

  int lyricsAiCompletelyWrongSkip;

  int lyricsAiIncorrectTextYes;

  int lyricsAiPhrasesNotRelatedYes;

  int lyricsImplicitlyOk;

  int lyricsReportCompletelyWrong;

  int lyricsRichsyncAdded;

  int trackInfluencerBonusModeratorVote;

  int lyricsAiMoodAnalysisV3Value;

  int lyricsAiUgcLanguage;

  int lyricsRankingChange;

  int trackStructure;

  int trackCompleteMetadata;

  int evaluationAcademyTest;

  int lyricsReportContainMistakes;
}
