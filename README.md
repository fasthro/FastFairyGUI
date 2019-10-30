# FastFairyGUI

导出Lua代码

-- 编辑器自定义属性
--- gen_lua: 生成lua代码 [true]
--- gen_lua_path: 生成lua代码完整路径
--- gen_lua_spas: 组件精准类型导出(例如:com.asButton) [true]
--- gen_define_path: require define 基础路径(例如:fairy, require("fairy/..."))
--- gen_lua_prefix: 导出文件名前缀标识(可忽略此项)

-- 名称前缀定义 (其他的可不写,主要用于自动导出代码，作为标识，准确锁定组件类型，如果没有定义前缀，会自动类型为GComponent)
--- button: btn_
--- comboBox: cb_
--- label: lab_
--- progress: pb_
--- slider: sl_
--- ignore: ig_
