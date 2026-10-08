# Dracula theme for Kakoune
#
# Face names follow the Dracula/Kakoune convention: syntax faces
# are lower case, user-interface faces are CamelCase, as registered
# by Kakoune (see `:doc faces`).
#
# See the LICENSE file at the top of the project tree for copyright
# and license details.

# Palette --------------------------------------------------------------------
declare-option str dracula_background      '282a36'
declare-option str dracula_background_dark '21222c'
declare-option str dracula_selection       '44475a'
declare-option str dracula_comment         '6272a4'
declare-option str dracula_foreground      'f8f8f2'
declare-option str dracula_red             'ff5555'
declare-option str dracula_orange          'ffb86c'
declare-option str dracula_yellow          'f1fa8c'
declare-option str dracula_green           '50fa7b'
declare-option str dracula_purple          'bd93f9'
declare-option str dracula_cyan            '8be9fd'
declare-option str dracula_pink            'ff79c6'

# Alpha blending
declare-option str dracula_cursor_alpha    '99'
declare-option str dracula_selection_alpha '80'

# Syntax ---------------------------------------------------------------------
set-face global value         "rgb:%opt{dracula_purple}"
set-face global type          "rgb:%opt{dracula_pink}"
set-face global variable      "rgb:%opt{dracula_cyan}"
set-face global module        "rgb:%opt{dracula_yellow}"
set-face global function      "rgb:%opt{dracula_green}"
set-face global string        "rgb:%opt{dracula_yellow}"
set-face global keyword       "rgb:%opt{dracula_pink}"
set-face global operator      "rgb:%opt{dracula_pink}"
set-face global attribute     "rgb:%opt{dracula_pink}"
set-face global comment       "rgb:%opt{dracula_comment}"
set-face global documentation comment
set-face global meta          "rgb:%opt{dracula_pink}"
set-face global builtin       "rgb:%opt{dracula_cyan}+i"

# Diffs ----------------------------------------------------------------------
set-face global DiffText      "rgb:%opt{dracula_comment}"
set-face global DiffHeader    "rgb:%opt{dracula_comment}"
set-face global DiffInserted  "rgb:%opt{dracula_green},rgba:%opt{dracula_green}20"
set-face global DiffDeleted   "rgb:%opt{dracula_red},rgba:%opt{dracula_red}50"
set-face global DiffChanged   "rgb:%opt{dracula_orange}"

# Markup ---------------------------------------------------------------------
set-face global title         "rgb:%opt{dracula_purple}+b"
set-face global header        "rgb:%opt{dracula_purple}+b"
set-face global mono          "rgb:%opt{dracula_green}"
set-face global block         "rgb:%opt{dracula_orange}"
set-face global link          "rgb:%opt{dracula_cyan}"
set-face global bullet        "rgb:%opt{dracula_cyan}"
set-face global list          "rgb:%opt{dracula_foreground}"

# User interface -------------------------------------------------------------
set-face global Default            "rgb:%opt{dracula_foreground},rgb:%opt{dracula_background}"
set-face global PrimarySelection   "default,rgba:%opt{dracula_pink}%opt{dracula_selection_alpha}"
set-face global SecondarySelection "default,rgba:%opt{dracula_purple}%opt{dracula_selection_alpha}"
set-face global PrimaryCursor      "default,rgba:%opt{dracula_pink}%opt{dracula_cursor_alpha}"
set-face global SecondaryCursor    "default,rgba:%opt{dracula_purple}%opt{dracula_cursor_alpha}"
set-face global PrimaryCursorEol   "rgb:%opt{dracula_background},rgb:%opt{dracula_foreground}+fg"
set-face global SecondaryCursorEol "rgb:%opt{dracula_background},rgb:%opt{dracula_foreground}+fg"
set-face global MenuForeground     "rgb:%opt{dracula_foreground},rgb:%opt{dracula_selection}"
set-face global MenuBackground     "rgb:%opt{dracula_foreground},rgb:%opt{dracula_background_dark}"
set-face global MenuInfo           "rgb:%opt{dracula_comment}"
set-face global Information        Default
set-face global Error              "rgb:%opt{dracula_foreground},rgb:%opt{dracula_red}"
set-face global DiagnosticError    "rgb:%opt{dracula_red}"
set-face global DiagnosticWarning  "rgb:%opt{dracula_cyan}"
set-face global StatusLine         "rgb:%opt{dracula_foreground},rgb:%opt{dracula_background_dark}"
set-face global StatusLineMode     "rgb:%opt{dracula_green}"
set-face global StatusLineInfo     "rgb:%opt{dracula_purple}"
set-face global StatusLineValue    "rgb:%opt{dracula_green}"
set-face global StatusCursor       "rgb:%opt{dracula_background},rgb:%opt{dracula_foreground}"
set-face global Prompt             StatusLine
set-face global BufferPadding      "rgb:%opt{dracula_background_dark}"

# Built-in highlighters ------------------------------------------------------
set-face global LineNumbers        "rgb:%opt{dracula_comment}"
set-face global LineNumberCursor   "rgb:%opt{dracula_foreground}"
set-face global LineNumbersWrapped "rgb:%opt{dracula_background}"
set-face global MatchingChar       "rgb:%opt{dracula_green}+uf"
set-face global Whitespace         "rgb:%opt{dracula_comment}+f"
set-face global WrapMarker         "rgb:%opt{dracula_comment}"
