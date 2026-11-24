# Changing what a view shows

Every change goes through `update_atlas`, which runs the view's own tools that change what it shows, and it lands in the tab the view relays to: the last one opened. When that is his tab, his screen changes. When the session opened its own tab, he sees the change only through a screenshot or the saved state: say which.

1. Call the view's own best-practices tool first and follow it.
2. Read the chart, chart-state and layout schemas from the view before writing a spec, never from memory: they change between versions.
3. What the view calls a layout is a tab inside the view. When he asks for something «in a new tab», create a layout; never open a second browser tab on the view for it, because the view would relay to that tab.
4. Build in a new layout. Leave his charts, filters and layout order as they are unless he asked for that change.
5. Colouring the map by a column is a setting of the map's own chart, found in the chart schemas. A column style is something else: it changes how a column's values are drawn in the table, the cards and the tooltip; read the list of supported styles from the view before setting one.
6. After any change, take a screenshot of the app and check that it shows what was intended.
7. To keep what was built, read the full app state from the view and save it as a file in the folder he names; ask where when he named none.

Say in the reply what was added or changed, and where the state was saved.
