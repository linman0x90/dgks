import os

# The repository root (this file is in tests/)
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Prepends dgks.lua's real name helpers (dgks.SplitName, dgks.PlayerFullName, dgks.UsesSurnames)
# to module files, for tests that load a module without dgks.lua.
MODULES = {"dgks_history.lua", "dgks_players.lua", "dgks_history_ui.lua", "dgks_window.lua",
           "dgks_deathrecap.lua", "dgks_minimap.lua"}


def helper(repo):
    s = open(f"{repo}/dgks.lua", encoding="utf-8").read().replace("\r\n", "\n")
    i = s.index("-- Forever: characters have a first name")
    j = s.index("function dgks.PlayerFullName()")
    j = s.index("\nend\n", j) + 5
    return s[i:j]


def wrap(src, repo):
    pre = ("if dgks and not dgks.SplitName then\n"
           "local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) == true end\n"
           + helper(repo) + "\nend\n")

    def new(f):
        t = src(f)
        return pre + t if f in MODULES else t
    return new
