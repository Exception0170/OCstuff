return {
  id="system",title="System",config="core",
  fields={
    {key="text_editor",section="system",label="Text editor",kind="app",default="/ltde/apps/notepad.app",live="config"},
    {key="chksys",section="system",label="System file check",kind="boolean",default=true,restart=true},
    {key="memory_check",section="system",label="Memory monitoring",kind="boolean",default=true,restart=true},
    {key="memory_warn_kb",section="system",label="Memory warning",kind="number",default=48,min=1,max=1024,integer=true,unit="KB",restart=true},
    {key="memory_critical_kb",section="system",label="Memory critical",kind="number",default=16,min=1,max=1024,integer=true,unit="KB",restart=true},
    {key="renderer_fps",section="system",label="Renderer FPS",kind="number",default=20,min=1,max=60,integer=true,restart=true},
    {key="log_keep",section="system",label="Log history",kind="number",default=10,min=0,max=1000,integer=true,restart=true},
    {key="enabled",section="splash",label="Startup splash",kind="boolean",default=true,restart=true},
    {key="delay",section="splash",label="Splash delay",kind="number",default=0.25,min=0,max=5,unit="seconds",restart=true}
  }
}
