Custom opinionated Neovim statuscolumn, similar to folke's statuscolumn in the snacks mega repo.

DAP, marks, and diagnostics icons are in the left column, git and folds in the right column.

[Example](./example.png)

Lazy plugin:

```lua
return {
    "coreyb-git/statuscolumn.nvim"
}
```

No setup call or opts required.  Just load the plugin and it does its thing.

Handles both GitSigns and MiniDiff icons.
