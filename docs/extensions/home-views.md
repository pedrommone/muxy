# Home Views

Home views are full-window extension webviews displayed outside project tabs. Showing one does not close, recreate, or suspend restored terminal sessions.

## Manifest

Declare one or more views under `homeViews`:

```json
{
  "muxy": {
    "homeViews": [
      {
        "id": "overview",
        "title": "Overview",
        "icon": "rectangle.3.group",
        "entry": "overview/index.html"
      }
    ],
    "commands": [
      {
        "id": "open-overview",
        "title": "Open Overview",
        "action": { "kind": "openHome", "homeView": "overview" }
      }
    ]
  }
}
```

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | string | yes | Stable identifier unique within the extension. |
| `title` | string | yes | Window and native top-bar title. |
| `icon` | icon | no | SF Symbol or extension SVG. |
| `entry` | string | yes | HTML entry inside the extension build output. |
| `defaultData` | object | no | Initial `window.muxy.data`. |

Users can choose an enabled home view under **Settings → Interface → Launch Screen**. Muxy falls back to the workspace when the selected extension is disabled or unavailable. Extensions cannot select themselves as the launch screen.

The persistent Home button reopens the selected launch view. `muxy.lifecycle.close()` and workspace navigation return to the existing workspace without changing its restored state.

The title-bar close button and Back action honor `muxy.lifecycle.onBeforeClose`. Selecting workspace content force-closes the home view so the requested navigation can complete, matching project-switch behavior for other extension surfaces.

## Building an overview

Use source-state APIs and derive presentation state inside the extension:

```js
const [projects, worktrees, agents, unread] = await Promise.all([
  muxy.projects.list({ scope: "all" }),
  muxy.worktrees.list({ scope: "all" }),
  muxy.agents.list({ scope: "pane" }),
  muxy.notifications.unreadCounts(),
]);
```

Subscribe to `agents.changed`, `notifications.changed`, `worktrees.changed`, and `repository.changed`, then refetch only the affected records. `repository.changed` covers the active local worktree; refresh other visible worktrees lazily after navigation or related invalidation events. Use cached `muxy.git.status({ project, worktree })` calls for visible or stale worktrees instead of polling every repository.

Use `muxy.navigation.focus({ paneID })` to leave the home view and focus the pane's project, worktree, area, and tab atomically.
