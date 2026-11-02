return {
  id="appearance",title="Appearance",config="display",
  fields={
    {key="wallpaper",section="",label="Wallpaper color",kind="color",default="cyan",
      choices={"white","gold","magenta","lightblue","yellow","lime","pink","darkgray",
        "lightgray","cyan","purple","darkblue","brown","darkgreen","red","black"},live="wallpaper"},
    {key="drag_cursor",section="",label="Drag cursor",kind="text",default="+",maxWidth=1,
      live="drag_cursor"},
    {key="screen_off_timeout",section="",label="Screen off timeout",kind="number",default=300,
      min=0,max=86400,integer=true,unit="seconds (0 disables)",live="config"}
  }
}
