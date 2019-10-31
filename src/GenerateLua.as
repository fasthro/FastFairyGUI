package {

import fairygui.editor.plugin.ICallback;
import fairygui.editor.plugin.IFairyGUIEditor;
import fairygui.editor.plugin.IPublishData;
import fairygui.editor.plugin.IPublishHandler;
import fairygui.editor.publish.FileTool;

import flash.debugger.enterDebugger;

import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

import fairygui.editor.plugin.IEditorUIProject;

import flash.globalization.StringTools;

public final class GenerateLua implements IPublishHandler {

    private var _editor:IFairyGUIEditor;

    private var _data:IPublishData;
    private var _callback:ICallback;

    /** 包名 */
    private var _pname:String;
    /** 导出根路径 */
    private var _ebpath:String;
    /** 导出路径 */
    private var _epath:String;
    /** 模版文件路径 */
    private var _ctpath:String;
    /** define 基础路径 */
    private var _dpath:String;
    /** 组件精准导出(例如：.asButton) */
    private var _spas:Boolean;
    /** lua文件 前缀缀 */
    private var _prefix:String;

    /** 是否生成 window */
    private var _genwindow:Boolean;
    /** window 路径 */
    private var _wpath:String;
    /** window 模路径 */
    private var _wtpath:String;

    public function GenerateLua(editor:IFairyGUIEditor) {
        this._editor = editor
    }

    public function doExport(data:IPublishData, callback:ICallback):Boolean {
        this._data = data;
        this._callback = callback;

        /** 清理日志 */
        clearlog();

        /** 是否导出 */
        var gen_lua:Boolean = this._editor.project.customProperties["gen_lua"] == "true";
        log("is_gen_lua:" + gen_lua.toString());
        if (!gen_lua) return false;

        /** 导出基础路径 */
        this._ebpath = this._editor.project.customProperties["gen_lua_path"]
        if (this._ebpath == null) {
            this._editor.alert("path_gen_lua:null");
            return false;
        }

        /** class 前缀 */
        this._prefix = this._editor.project.customProperties["gen_lua_prefix"]
        if (this._prefix == null) this._prefix = "";

        /**component模版文件路径 */
        this._ctpath = combinePath(this._editor.project.basePath, "/template/component_lua.template");
        if (!existsPath(this._ctpath)) {
            this._editor.alert("component_lua.template does not exist!");
            return false;
        }

        /** define 路径 */
        this._dpath = this._editor.project.customProperties["gen_define_path"];
        if (this._dpath == null) this._dpath = "";

        /** 组件精准导出 */
        this._spas = this._editor.project.customProperties["gen_lua_spas"] == "true";

        /** 生成window */
        this._genwindow = this._editor.project.customProperties["gen_lua_window"] == "true";


        if (this._genwindow == true) {
            /** window 导出路径 */
            this._wpath = this._editor.project.customProperties["gen_lua_window_path"];
            if (this._wpath == null) {
                this._editor.alert("gen_lua_window_path：null");
                return false;
            }

            /**window模版文件路径 */
            this._wtpath = combinePath(this._editor.project.basePath, "/template/window_lua.template");
            if (!existsPath(this._wtpath)) {
                this._editor.alert("window_lua.template does not exist!");
                return false;
            }
        }

        /** 执行导出 */
        init();

        /** 生成 define.lua */
        genRequireDefine();

        callback.callOnSuccess();
        return true;
    }

    private function init():void {
        this._pname = this._data.targetUIPackage.name;
        this._epath = combinePath(this._ebpath, this._pname);

        log("package_name:" + this._pname);
        log("export_path:" + this._epath);
        log(">>>>> start " + this._pname + " gen lua");

        reCreateDirectory(this._epath);

        for each(var classInfo:Object in this._data.outputClasses) {
            log("> classId:" + classInfo.classId + " className:" + classInfo.className + " superClassName:" + classInfo.superClassName + " members:" + classInfo.members);
            for (var i:int = 0; i < classInfo.members.length; i++) {
                var str:String = "name:" + classInfo.members[i].name;
                str += " type:" + classInfo.members[i].type;
                if (classInfo.members[i].src != null) {
                    str += " src:" + classInfo.members[i].src;
                }

                if (classInfo.members[i].pkg != null) {
                    str += " pkg:" + classInfo.members[i].pkg;
                }
                log(str);
            }
            exportClass(classInfo);
            if (this._genwindow) exportWindowClass(classInfo);
        }
    }

    private function genRequireDefine():void {
        var lcs:Array = []
        lcs.push("--[[ aotu generated from fastfairy plugin]]");
        var dirs:Array = FileTool.getSubFolders(this._ebpath);
        for each(var dir:File in dirs) {
            var files:Array = dir.getDirectoryListing();
            lcs.push("-- " + getDirectoryName(dir.url));
            for each(var file:File in files) {
                var fileDir:File = file.resolvePath("..");
                var packName:String = getDirectoryName(fileDir.url);
                var filename:String = getFileName(file, true);
                if (filename.indexOf(".meta") == -1) {
                    var index:int = filename.indexOf(".lua");
                    if (index > 0) {
                        var className:String = filename.replace(".lua", "");
                        if (this._dpath == "") {
                            lcs.push('require(\"' + packName + "/" + className + '\")');
                        } else {
                            lcs.push('require(\"' + this._dpath + "/" + packName + "/" + className + '\")');
                        }
                    }
                }
            }
        }

        FileTool.writeFile(combinePath(getParentDirectory(this._epath), "/define.lua"), lcs.join("\r"));
    }

    private function exportClass(classInfo:Object):void {
        // component type
        var comType:String = classInfo.superClassName;
        // component name
        var comName:String = classInfo.className;

        // lua file path
        var classPath:String = combinePath(this._epath, getClassName(comName));
        // component url
        var classUrl:String = "ui://" + this._data.targetUIPackage.name + "/" + comName;

        // template context
        var template:String = FileTool.readByteByFile(new File((this._ctpath))).toString();

        template = template.replace("{export_com_type}", comType);
        template = template.replace("{export_url}", classUrl);

        var childList:Array = [];
        for each(var memberInfo:Object in classInfo.members) {
            if (!ignore(memberInfo.name)) {
                var field:String = "self.ui." + memberInfo.name;
                var code:String = getComponentChildCode(memberInfo.type, memberInfo.name);
                childList.push("\t" + field + " = " + code);

                // 事件绑定
                var button:Boolean = isButton(memberInfo.name)
                if (button) childList.push("\tfui.bind_click_event(self.ui." + memberInfo.name + ", self, " + '\"' + memberInfo.name + '\", self.on_click)');
            }
        }

        template = template.replace("{export_child}", childList.join("\r\n"));

        FileTool.writeFile(classPath, template);
    }

    private function exportWindowClass(classInfo:Object):void {
        // component name
        var comName:String = classInfo.className;
        if (iswindow(comName)) {
            var fp:String = combinePath(this._wpath, comName + ".lua");
            if (!existsPath(fp)) {
                var template:String = FileTool.readByteByFile(new File((this._wtpath))).toString();
                template = template.replace("{component_name}", comName);
                template = template.replace("{package_name}", this._pname);

                var callList:Array = [];
                for each(var memberInfo:Object in classInfo.members) {
                    if (!ignore(memberInfo.name)) {
                        // 生成事件回调
                        var button:Boolean = isButton(memberInfo.name)
                        if (button) callList.push("function window:" + memberInfo.name + "_onclick(context)\nend");
                    }
                }

                template = template.replace("{callback_function}", callList.join("\r\n"));

                FileTool.writeFile(fp, template);
            }
        }
    }

    private function iswindow(name:String):Boolean {
        var cnl:int = name.length;
        var len:int = "_window".length;
        var si:int = cnl - len;
        if (si > 0) {
            if (name.substr(si, len) == "_window") {
                return true;
            }
        }
        return false;
    }

    private function ignore(name:String):Boolean {
        var index:int = name.indexOf("_");
        if (index > -1) {
            var ts:String = name.substr(0, index);
            if (ts == "ig") {
                return true;
            }
        }
        return false;
    }

    private function getClassName(cname:String):String {
        if (this._prefix == "")
            return "/" + cname + ".lua";
        return "/" + this._prefix + "_" + cname + ".lua";
    }

    private function getComponentChildCode(t:String, name:String):String {
        if (t == "Controller") {
            return "self:GetController(\"" + name + "\");"
        } else if (t == "Transition") {
            return "self:GetTransition(\"" + name + "\");"
        } else {
            return "self:GetChild(\"" + name + "\")." + getComponentAsType(t, name) + ";"
        }
    }

    private function getComponentAsType(t:String, name:String):String {
        if (t == "GImage") {
            return "asImage";
        } else if (t == "GComponent") {
            return getSpecialComponentAsType(name);
        } else if (t == "GButton") {
            return "asButton";
        } else if (t == "GLabel") {
            return "asLabel";
        } else if (t == "GProgressBar") {
            return "asProgress";
        } else if (t == "GSlider") {
            return "asSlider";
        } else if (t == "GComboBox") {
            return "asComboBox";
        } else if (t == "GTextField") {
            return "asTextField";
        } else if (t == "GRichTextField") {
            return "asRichTextField";
        } else if (t == "GTextInput") {
            return "asTextInput";
        } else if (t == "GLoader") {
            return "asLoader";
        } else if (t == "GList") {
            return "asList";
        } else if (t == "GGraph") {
            return "asGraph";
        } else if (t == "GGroup") {
            return "asGroup";
        } else if (t == "GMovieClip") {
            return "asMovieClip";
        } else if (t == "GTree") {
            return "asTree";
        } else if (t == "GTreeNode") {
            return "treeNode";
        }
        return "";
    }

    private function getSpecialComponentAsType(name:String):String {
        var index:int = name.indexOf("_");
        if (index > -1) {
            var ts:String = name.substr(0, index);
            if (ts == "btn") {
                return "asButton";
            } else if (ts == "cb") {
                return "asComboBox";
            } else if (ts == "lab") {
                return "asLabel";
            } else if (ts == "pb") {
                return "asProgress";
            } else if (ts == "sl") {
                return "asSlider";
            }
        }
        return "asCom"
    }

    private function isButton(name:String):Boolean {
        var index:int = name.indexOf("_");
        if (index > -1) {
            var ts:String = name.substr(0, index);
            if (ts == "btn") {
                return true;
            }
        }
        return false;
    }

    /** 打印日志 */
    private function log(msg:String):void {
        var path:String = this._editor.project.basePath + "/log.txt";
        var file:File = new File(path);
        var fileStream:FileStream = new FileStream();
        fileStream.open(file, FileMode.APPEND);
        fileStream.writeUTFBytes(msg + "\n");
        fileStream.close();
    }

    /** 清理日志 */
    private function clearlog():void {
        var path:String = this._editor.project.basePath + "/log.txt";
        var file:File = new File(path);
        if (file.exists) {
            file.deleteFile();
        }
    }

    public function reCreateDirectory(path:String):void {
        var file:File = new File(path);
        if (file.exists) file.deleteDirectory(true);
        file.createDirectory();
    }

    public function createDirectory(path:String):void {
        var file:File = new File(path);
        if (!file.exists) file.createDirectory();
    }

    public function deleteDirectory(path:String):void {
        var file:File = new File(path);
        if (!file.exists) file.deleteDirectory(true);
    }

    public function getDirectoryName(path:String):String {
        var dir:File = new File(path);
        var parent:File = dir.resolvePath("..")
        var dn:String = dir.url.replace(parent.url, "");
        if (dn.indexOf("/") > -1) return dn.replace("/", "");
        if (dn.indexOf("\\") > -1) return dn.replace("\\", "");
        return dn;
    }

    public function getParentDirectory(path:String):String {
        var dir:File = new File(path);
        return dir.resolvePath("..").url;
    }

    public function getFileName(file:File, hpx:Boolean):String {
        var dir:File = file.resolvePath("..")
        var fn:String = file.url.replace(dir.url, "");
        if (fn.indexOf("/") > -1) fn = fn.replace("/", "");
        if (fn.indexOf("\\") > -1) fn = fn.replace("\\", "");
        if (hpx) return fn;
        var index:int = fn.indexOf('.');
        if (index > -1) return fn.substr(0, index);
        return fn;
    }

    public function existsPath(path:String):Boolean {
        var file:File = new File(path);
        return file.exists;
    }

    public function combinePath(path1:String, path2:String):String {
        return path1 + path2;
    }
}
}