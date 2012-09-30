#include <sourcemod>
#include <regex>
#include <colors>
#include <sdktools>

#define UPDATE_URL "http://dl.dropbox.com/u/83581539/urlchatblock.txt"

#undef REQUIRE_PLUGIN
#include <updater>
#define REQUIRE_PLUGIN

new bool:g_bEnabled,
	bool:g_bImmunity,
	bool:g_bLogVerbose,
	bool:g_bShowMessage,
	bool:g_bWhitelist,
	bool:g_bAutoUpdate;

new String:g_strWhiteListPath[PLATFORM_MAX_PATH];

new Handle:g_hRegex,
	Handle:g_hArray = INVALID_HANDLE;

#define PLUGIN_VERSION "3.1.0"
#define REGEX_STRING "(((file|gopher|news|nntp|telnet|http|ftp|https|ftps|sftp)://)|(www\\.))+(([a-zA-Z0-9\\._-]+\\.[a-zA-Z]{2,6})|([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}))(/[a-zA-Z0-9\\&amp;%_\\./-~-]*)?"

public Plugin:myinfo = 
{
	name = "URL Chat Block",
	author = "Mini",
	description = "Blocks people from posting a website address in chat.",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net"
};

public OnPluginStart()
{
	new Handle:conVar;
	conVar = CreateConVar("sm_urlchatblock_enabled", "1", "Enable or disable the URL Chat Block plugin", _, true, 0.0, true, 1.0);
	g_bEnabled = GetConVarBool(conVar);
	HookConVarChange(conVar, OnEnableChanged);
	conVar = CreateConVar("sm_urlchatblock_use_immunity", "1", "Should this plugin use immunity to decide if someone can post a URL or not?");
	g_bImmunity = GetConVarBool(conVar);
	HookConVarChange(conVar, OnImmunityChange);
	conVar = CreateConVar("sm_urlchatblock_log", "1", "Enable or disable the logging of people's URL blocks.", _, true, 0.0, true, 1.0);
	g_bLogVerbose = GetConVarBool(conVar);
	HookConVarChange(conVar, OnLogChange);
	conVar = CreateConVar("sm_urlchatblock_show_message_to_author", "1", "Show message to the author so he/she would not realize the block.", _, true, 0.0, true, 1.0);
	g_bShowMessage = GetConVarBool(conVar);
	HookConVarChange(conVar, OnAuthorChange);
	conVar = CreateConVar("sm_urlchatblock_whitelist", "1", "Use a whitelist?");
	g_bWhitelist = GetConVarBool(conVar);
	HookConVarChange(conVar, OnWhitelistChange);
	conVar = CreateConVar("sm_urlchatblock_whitelist_path", "configs/ucb_whitelist.txt", "The path to the whitelist file.");
	GetConVarString(conVar, g_strWhiteListPath, sizeof(g_strWhiteListPath));
	BuildPath(Path_SM, g_strWhiteListPath, sizeof(g_strWhiteListPath), g_strWhiteListPath);
	HookConVarChange(conVar, OnWhiteListPathChange);

	conVar = CreateConVar("sm_urlchatblock_autoupdate", "1", "Auto Update?");
	g_bAutoUpdate = GetConVarBool(conVar);
	HookConVarChange(conVar, OnAutoUpdateChange);

	AddCommandListener(Command_Chat, "say");
	AddCommandListener(Command_Chat, "say_team");
	AddCommandListener(Command_Chat, "say2");

	RegAdminCmd("sm_ucb_reload", ReloadWhiteList, ADMFLAG_RCON);

	g_hRegex = CompileRegex(REGEX_STRING, PCRE_CASELESS);

	g_hArray = CreateArray(256);

	ParseWhiteList();
}
/**
 *
 * Credit for auto updater functions goes to Dr. Mckay
 *
 * @note PLEACE
 * @note YOU ARE BIRD
 *
 */

public OnAllPluginsLoaded()
{
	new Handle:convar;
	if (LibraryExists("updater")) 
	{
		Updater_AddPlugin(UPDATE_URL);
		new String:newVersion[10];
		Format(newVersion, sizeof(newVersion), "%sA", PLUGIN_VERSION);
		convar = CreateConVar("sm_urlchatblock_version", newVersion, "URL Chat Block Version", FCVAR_DONTRECORD|FCVAR_NOTIFY|FCVAR_CHEAT);
	} 
	else 
	{
		convar = CreateConVar("sm_urlchatblock_version", PLUGIN_VERSION, "URL Chat Block Version", FCVAR_DONTRECORD|FCVAR_NOTIFY|FCVAR_CHEAT);	
	}
	HookConVarChange(convar, OnVersionChanged);
}

public OnVersionChanged(Handle:convar, const String:oldValue[], const String:newValue[]) 
{
	decl String:defaultValue[32];
	GetConVarDefault(convar, defaultValue, sizeof(defaultValue));
	if (!StrEqual(newValue, defaultValue)) 
	{
		SetConVarString(convar, defaultValue);
	}
}

public Action:Updater_OnPluginDownloading() 
{
	if (g_bAutoUpdate) 
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Updater_OnPluginUpdated() 
{
	ReloadPlugin();
}

public OnLibraryAdded(const String:name[])
{
	if (!strcmp(name, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public OnLibraryRemoved(const String:name[])
{
	if (!strcmp(name, "updater"))
	{
		Updater_RemovePlugin();
	}
}

public Action:ReloadWhiteList(client, args)
{
	if (g_hArray != INVALID_HANDLE)
		ClearArray(g_hArray);
	ParseWhiteList();
	ReplyToCommand(client, "[SM] The URL Chat Block config has been successfully reloaded.");
	return Plugin_Handled;
}

stock ParseWhiteList()
{
	if (FileExists(g_strWhiteListPath)) 
	{
		decl String:strBuffer[256], String:strBuffer2[256];
		if (g_hArray != INVALID_HANDLE)
			ClearArray(g_hArray);
		new Handle:keyValues = CreateKeyValues("URL Chat Block Whitelist");
		if (FileToKeyValues(keyValues, g_strWhiteListPath))
		{
			KvGetSectionName(keyValues, strBuffer, sizeof(strBuffer));
			if (KvGotoFirstSubKey(keyValues))
			{
				do
				{
					KvGetString(keyValues, "url", strBuffer2, sizeof(strBuffer2));
					PushArrayString(g_hArray, strBuffer2);
				}				
				while (KvGotoNextKey(keyValues));
				KvGoBack(keyValues);
			}	
			
		}
	} 
	else 
	{
		LogError("URL Chat Block whitelist file \"%s\" could not be found.", g_strWhiteListPath);
	}
}

public Action:Command_Chat(client, const String:command[], args)
{
	if (g_bEnabled && (g_bImmunity && !CheckCommandAccess(client, "sm_urlchatblock_immune", ADMFLAG_ROOT)) || !g_bImmunity)
	{
		decl String:message[256], String:match[128], String:arrayUrl[512];
		GetCmdArgString(message, sizeof(message));
		StripQuotes(message);
		if (MatchRegex(g_hRegex, message) > 0)
		{
			if (!g_bWhitelist || g_hRegex == INVALID_HANDLE)
			{
				if (g_bLogVerbose)
				{
					LogMessage("[URLChatBlock] %L tried to post a URL in the chat. Blocked.", client);
				}
				if (g_bShowMessage)
				{
					ShowMessageToAuthor(client, command, message);
				}
				return Plugin_Handled;
			}

			GetRegexSubString(g_hRegex, 0, match, sizeof(match));

			for (new i = 0; i < GetArraySize(g_hArray); i++)
			{
				GetArrayString(g_hArray, i, arrayUrl, sizeof(arrayUrl));
				if (StrContains(match, arrayUrl, false) != -1)
				{
					if (g_bLogVerbose)
					{
						LogMessage("[URLChatBlock] %L tried to post a URL in the chat. Allowed because it was in the whitelist.", client);
					}
					return Plugin_Continue;
				}
			}

			if (g_bLogVerbose)
			{
				LogMessage("[URLChatBlock] %L tried to post a URL in the chat. Blocked.", client);
			}
			if (g_bShowMessage)
			{
				ShowMessageToAuthor(client, command, message);
			}
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

stock ShowMessageToAuthor(client, const String:command[], const String:message[])
{
	decl String:tag[16];
	tag[0] = '\0';
	new bool:spec = (GetClientTeam(client) <= 1) ? true : false;
	if (spec)
		tag = "*SPEC* ";
	else if (!IsPlayerAlive(client))
		tag = "*DEAD* ";
	if (!strcmp(command, "say", false))
	{
		CPrintToChatEx(client, client, "%s{teamcolor}%N{default} : %s", tag, client, message);
	}
	else
	{
		decl String:clientTeam[64];
		GetTeamName(GetClientTeam(client), clientTeam, sizeof(clientTeam));
		CPrintToChatEx(client, client, "%s(%s) {teamcolor}%N{default} : %s", (spec ? "" : tag), clientTeam, client, message);
	}
}

public OnEnableChanged(Handle:conVar, const String:oldVal[], const String:newVal[])
{
	g_bEnabled = bool:StringToInt(newVal);
}

public OnImmunityChange(Handle:conVar, const String:oldVal[], const String:newVal[])
{
	g_bImmunity = bool:StringToInt(newVal);
}

public OnLogChange(Handle:conVar, const String:oldVal[], const String:newVal[])
{
	g_bLogVerbose = bool:StringToInt(newVal);
}

public OnAuthorChange(Handle:conVar, const String:oldVal[], const String:newVal[])
{
	g_bShowMessage = bool:StringToInt(newVal);
}

public OnWhitelistChange(Handle:conVar, const String:oldVal[], const String:newVal[])
{
	g_bWhitelist = bool:StringToInt(newVal);
}

public OnWhiteListPathChange(Handle:conVar, const String:oldVal[], const String:newVal[])
{
	BuildPath(Path_SM, g_strWhiteListPath, sizeof(g_strWhiteListPath), newVal);
	if (g_bWhitelist)
		ParseWhiteList();
}

public OnAutoUpdateChange(Handle:conVar, const String:oldVal[], const String:newVal[])
{
	g_bAutoUpdate = bool:StringToInt(newVal);
}

public OnPluginEnd()
{
	if (g_hArray != INVALID_HANDLE)
	{
		CloseHandle(g_hArray);
	}
}