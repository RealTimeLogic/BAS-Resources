# Web File Manager commands

The Web File Manager (WFM) separates operations on the displayed folder from
operations on selected files or folders. This guide describes the shared
[browser module](../src/core/wfm/wfm.js) used by Mako Server and Xedge, including
command placement for client plugins.

## Choose the target

The **Current folder** toolbar group contains Refresh, Upload, New window,
New folder, and the optional Search command. These operate on the folder shown
in the breadcrumb. Search starts there even when another folder is selected.
Right-click empty space in the file area to open the same folder commands.

The **Selected** toolbar group identifies the selected item, or the number of
selected items. Its **More** menu and the item context menu contain the same
selection commands in the same order, including Copy Session URL and lock
operations. Delete appears last and is separated visually.

Right-clicking a tree folder selects it without changing the displayed folder.
The previous file selection is cleared. The current folder remains bold in the
tree; the selection has a background highlight. Built-in commands that do not
apply to the selection remain visible but disabled.

## Use the keyboard

Tab to **More** and press Enter or Space to open the menu. For a focused file
row, tree folder, or file area, use Shift+F10 or the Menu key. Up and Down move
between enabled commands, Home and End select the first and last enabled
commands, and Enter or Space activates a command. Escape closes the menu and
returns focus to its origin. Tab closes the menu and continues keyboard focus
navigation.

## Place a plugin command

Register commands with the existing `api.add("command", spec)` interface.
The optional string `spec.group` accepts `"selection"` (the default) or
`"folder"`. Use `"folder"` for commands whose target is the displayed folder;
read that path from the string `context.directory` in the callback.

Placement flags are optional booleans. `toolbar: false` removes a command from
the direct toolbar buttons. `menu: false` removes it from menus, including More.
Omitting either flag makes that placement available. A selection command with
`toolbar: false` is accessible through More and the item context menu.

For existing plugins, `showDisabled` retains its default of false: a command
whose synchronous `when(context)` predicate returns false is hidden in menus
and disabled in the toolbar. Set the optional boolean `showDisabled: true` to
match the built-in commands. These flags control presentation; the Web File
Server still enforces authorization.

`run(context, api)` is called only when the command is enabled. It may return
normally or return a Promise; failures are displayed in the status area.
The function returned by `api.add` unregisters the command. Return it from a
plugin so the manager also unregisters it during `destroy()`.

The [WFS reference](https://realtimelogic.com/ba/doc/en/lua/wfs.html) describes
server setup, the manager API, and the remaining plugin contracts.
