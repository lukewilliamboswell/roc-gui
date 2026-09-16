platform ""
	requires {
		[State : state] for main : Program(state)
	}
	exposes [Program, Elem, Action, Event, Gui, Files, Timer, Http, Sqlite, Clipboard, Tcp, Process, Audio, Device, SystemMonitor, ImageData, Assets]
	packages {
		roc: "nightly-2026-09-15-fe09c42",
		http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	}
	provides { "roc_gui_init": gui_init!, "roc_gui_dispatch": gui_dispatch!, "roc_gui_complete": gui_complete!, "roc_gui_run_task": gui_run_task! }
	hosted {
		"roc_gui_node_text": Host.node_text!,
		"roc_gui_node_styled_text": Host.node_styled_text!,
		"roc_gui_children_begin": Host.children_begin!,
		"roc_gui_children_push": Host.children_push!,
		"roc_gui_node_row": Host.node_row!,
		"roc_gui_node_column": Host.node_column!,
		"roc_gui_node_dialog": Host.node_dialog!,
		"roc_gui_node_panel": Host.node_panel!,
		"roc_gui_node_scroll": Host.node_scroll!,
		"roc_gui_node_action_button": Host.node_action_button!,
		"roc_gui_node_virtual_item": Host.node_virtual_item!,
		"roc_gui_node_virtual_list": Host.node_virtual_list!,
		"roc_gui_node_checkbox": Host.node_checkbox!,
		"roc_gui_node_textarea": Host.node_textarea!,
		"roc_gui_node_image": Host.node_image!,
		"roc_gui_node_canvas": Host.node_canvas!,
		"roc_gui_canvas_event": Host.canvas_event!,
		"roc_gui_input_value": Host.input_value!,
		"roc_gui_node_text_input": Host.node_text_input!,
		"roc_sqlite_open_read": Host.sqlite_open_read!,
		"roc_sqlite_query": Host.sqlite_query!,
		"roc_files_app_data": InternalFiles.app_data!,
		"roc_files_dir_read_utf8": InternalFiles.read_utf8!,
		"roc_files_dir_write_utf8_atomic": InternalFiles.write_utf8_atomic!,
		"roc_clipboard_acquire": Host.clipboard_acquire!,
		"roc_clipboard_read_text": Host.clipboard_read_text!,
		"roc_clipboard_write_text": Host.clipboard_write_text!,
		"roc_audio_acquire": Host.audio_acquire!,
		"roc_audio_load": Host.audio_load!,
		"roc_audio_play": Host.audio_play!,
		"roc_audio_pause": Host.audio_pause!,
		"roc_audio_seek": Host.audio_seek!,
		"roc_audio_status": Host.audio_status!,
		"roc_audio_stop": Host.audio_stop!,
		"roc_tcp_connect": Host.tcp_connect!,
		"roc_tcp_read_up_to": Host.tcp_read_up_to!,
		"roc_tcp_write_all": Host.tcp_write_all!,
		"roc_tcp_close": Host.tcp_close!,
		"roc_process_acquire": Host.process_acquire!,
		"roc_process_spawn": Host.process_spawn!,
		"roc_process_read": Host.process_read!,
		"roc_process_write": Host.process_write!,
		"roc_process_resize": Host.process_resize!,
		"roc_process_cancel": Host.process_cancel!,
		"roc_device_acquire": Host.device_acquire!,
		"roc_device_discover": Host.device_discover!,
		"roc_device_connect": Host.device_connect!,
		"roc_device_transact": Host.device_transact!,
		"roc_device_close": Host.device_close!,
		"roc_system_acquire": Host.system_acquire!,
		"roc_system_sample": Host.system_sample!,
		"roc_system_close": Host.system_close!,
		"roc_image_inspect": Host.image_inspect!,
		"roc_assets_open": Host.assets_open!,
		"roc_assets_read": Host.assets_read!,
		"roc_gui_apply": Host.apply!,
		"roc_gui_set_dispatch": Host.set_dispatch!,
		"roc_gui_set_task_dispatch": Host.set_task_dispatch!,
		"roc_gui_enqueue_task": Host.enqueue_task!,
		"roc_gui_timer_start": Host.timer_start!,
		"roc_gui_timer_next": Host.timer_next!,
		"roc_gui_timer_cancel": Host.timer_cancel!,
		"roc_http_send": Host.http_send!,
		"roc_http_acquire": Host.http_acquire!,
		"roc_gui_work_start": Host.work_start!,
		"roc_gui_work_end": Host.work_end!,
		"roc_gui_window_config": Host.window_config!,
		"roc_files_pick_directory": InternalFiles.pick_directory!,
		"roc_files_dir_list": InternalFiles.dir_list!,
		"roc_files_dir_open_read": InternalFiles.dir_open_read!,
		"roc_files_dir_read": InternalFiles.dir_read!,
	}
	targets: {
		inputs_dir: "targets/",
		x64glibc: { inputs: ["crt1.o", "libhost.a", app, "libasound.so", "libfreetype.so", "libxkbcommon.so", "libxkbcommon-x11.so", "libunwind.a", "libc_nonshared.a", "libm.so", "libc.so"] },
		arm64mac: { inputs: ["libhost.a", app, "../macos-sysroot/usr/lib/libSystem.tbd", "../macos-sysroot/usr/lib/libobjc.tbd", "../macos-sysroot/usr/lib/libc++.tbd"] },
		x64mingw: { inputs: ["crt2.obj", "libhost.a", "roc-gui.res", app, "api-ms-win-crt-conio-l1-1-0.lib", "api-ms-win-crt-convert-l1-1-0.lib", "api-ms-win-crt-environment-l1-1-0.lib", "api-ms-win-crt-filesystem-l1-1-0.lib", "api-ms-win-crt-heap-l1-1-0.lib", "api-ms-win-crt-locale-l1-1-0.lib", "api-ms-win-crt-math-l1-1-0.lib", "api-ms-win-crt-multibyte-l1-1-0.lib", "api-ms-win-crt-private-l1-1-0.lib", "api-ms-win-crt-process-l1-1-0.lib", "api-ms-win-crt-runtime-l1-1-0.lib", "api-ms-win-crt-stdio-l1-1-0.lib", "api-ms-win-crt-string-l1-1-0.lib", "api-ms-win-crt-time-l1-1-0.lib", "api-ms-win-crt-utility-l1-1-0.lib", "compiler_rt.lib", "libmingw32.lib", "ubsan_rt.lib", "unwind.lib", "zigc.lib", "ole32.lib", "activeds.lib", "advapi32.lib", "advpack.lib", "amsi.lib", "api-ms-win-appmodel-runtime-l1-1-1.lib", "api-ms-win-appmodel-runtime-l1-1-3.lib", "api-ms-win-appmodel-runtime-l1-1-6.lib", "api-ms-win-core-apiquery-l2-1-0.lib", "api-ms-win-core-backgroundtask-l1-1-0.lib", "api-ms-win-core-comm-l1-1-1.lib", "api-ms-win-core-comm-l1-1-2.lib", "api-ms-win-core-enclave-l1-1-1.lib", "api-ms-win-core-errorhandling-l1-1-3.lib", "api-ms-win-core-featurestaging-l1-1-0.lib", "api-ms-win-core-featurestaging-l1-1-1.lib", "api-ms-win-core-file-fromapp-l1-1-0.lib", "api-ms-win-core-handle-l1-1-0.lib", "api-ms-win-core-ioring-l1-1-0.lib", "api-ms-win-core-libraryloader-l2-1-0.lib", "api-ms-win-core-marshal-l1-1-0.lib", "api-ms-win-core-memory-l1-1-3.lib", "api-ms-win-core-memory-l1-1-4.lib", "api-ms-win-core-memory-l1-1-5.lib", "api-ms-win-core-memory-l1-1-6.lib", "api-ms-win-core-memory-l1-1-7.lib", "api-ms-win-core-memory-l1-1-8.lib", "api-ms-win-core-path-l1-1-0.lib", "api-ms-win-core-psm-appnotify-l1-1-0.lib", "api-ms-win-core-psm-appnotify-l1-1-1.lib", "api-ms-win-core-realtime-l1-1-1.lib", "api-ms-win-core-realtime-l1-1-2.lib", "api-ms-win-core-slapi-l1-1-0.lib", "api-ms-win-core-state-helpers-l1-1-0.lib", "api-ms-win-core-synch-l1-2-0.lib", "api-ms-win-core-sysinfo-l1-2-0.lib", "api-ms-win-core-sysinfo-l1-2-3.lib", "api-ms-win-core-sysinfo-l1-2-4.lib", "api-ms-win-core-sysinfo-l1-2-6.lib", "api-ms-win-core-util-l1-1-1.lib", "api-ms-win-core-winrt-error-l1-1-0.lib", "api-ms-win-core-winrt-error-l1-1-1.lib", "api-ms-win-core-winrt-l1-1-0.lib", "api-ms-win-core-winrt-registration-l1-1-0.lib", "api-ms-win-core-winrt-string-l1-1-0.lib", "api-ms-win-core-winrt-string-l1-1-1.lib", "api-ms-win-core-wow64-l1-1-1.lib", "api-ms-win-devices-query-l1-1-0.lib", "api-ms-win-devices-query-l1-1-1.lib", "api-ms-win-dx-d3dkmt-l1-1-0.lib", "api-ms-win-dx-d3dkmt-l1-1-4.lib", "api-ms-win-dx-d3dkmt-l1-1-6.lib", "api-ms-win-gaming-deviceinformation-l1-1-0.lib", "api-ms-win-gaming-expandedresources-l1-1-0.lib", "api-ms-win-gaming-tcui-l1-1-0.lib", "api-ms-win-gaming-tcui-l1-1-1.lib", "api-ms-win-gaming-tcui-l1-1-2.lib", "api-ms-win-gaming-tcui-l1-1-3.lib", "api-ms-win-gaming-tcui-l1-1-4.lib", "api-ms-win-mm-misc-l1-1-1.lib", "api-ms-win-net-isolation-l1-1-0.lib", "api-ms-win-security-base-l1-2-2.lib", "api-ms-win-security-isolatedcontainer-l1-1-0.lib", "api-ms-win-security-isolatedcontainer-l1-1-1.lib", "api-ms-win-service-core-l1-1-3.lib", "api-ms-win-service-core-l1-1-4.lib", "api-ms-win-service-core-l1-1-5.lib", "api-ms-win-shcore-scaling-l1-1-0.lib", "api-ms-win-shcore-scaling-l1-1-1.lib", "api-ms-win-shcore-scaling-l1-1-2.lib", "api-ms-win-shcore-stream-winrt-l1-1-0.lib", "api-ms-win-wsl-api-l1-1-0.lib", "apphelp.lib", "authz.lib", "avicap32.lib", "avifil32.lib", "avrt.lib", "bcp47mrm.lib", "bcrypt.lib", "bcryptprimitives.lib", "bluetoothapis.lib", "bthprops.lib", "cabinet.lib", "certadm.lib", "certpoleng.lib", "cfgmgr32.lib", "chakra.lib", "cldapi.lib", "clfs.lib", "clfsw32.lib", "clusapi.lib", "combase.lib", "comctl32.lib", "comdlg32.lib", "compstui.lib", "computecore.lib", "computenetwork.lib", "computestorage.lib", "comsvcs.lib", "coremessaging.lib", "credui.lib", "crypt32.lib", "cryptnet.lib", "cryptui.lib", "cryptxml.lib", "cscapi.lib", "d2d1.lib", "d3d11.lib", "d3dcompiler_47.lib", "d3dcsx.lib", "davclnt.lib", "dbgeng.lib", "dbghelp.lib", "dbgmodel.lib", "dciman32.lib", "dcomp.lib", "dflayout.lib", "dhcpcsvc.lib", "dhcpcsvc6.lib", "dhcpsapi.lib", "diagnosticdataquery.lib", "dinput8.lib", "dmprocessxmlfiltered.lib", "dnsapi.lib", "drt.lib", "drtprov.lib", "drttransport.lib", "dsparse.lib", "dsprop.lib", "dssec.lib", "dsuiext.lib", "dwmapi.lib", "dwrite.lib", "dxgi.lib", "dxva2.lib", "eappcfg.lib", "eappprxy.lib", "efswrt.lib", "elscore.lib", "esent.lib", "faultrep.lib", "fhsvcctl.lib", "firewallapi.lib", "fltlib.lib", "fltmgr.lib", "fontsub.lib", "fwpkclnt.lib", "fwpuclnt.lib", "fxsutility.lib", "gdi32.lib", "gdiplus.lib", "glu32.lib", "gpedit.lib", "hal.lib", "hhctrl.lib", "hid.lib", "hlink.lib", "httpapi.lib", "icm32.lib", "icmui.lib", "icu.lib", "icuin.lib", "icuuc.lib", "ieframe.lib", "imagehlp.lib", "imgutil.lib", "imm32.lib", "infocardapi.lib", "inkobjcore.lib", "iphlpapi.lib", "iscsidsc.lib", "isolatedwindowsenvironmentutils.lib", "kernel32.lib", "kernelbase.lib", "keycredmgr.lib", "ksecdd.lib", "ksproxy.lib", "ksuser.lib", "ktmw32.lib", "licenseprotection.lib", "loadperf.lib", "magnification.lib", "mapi32.lib", "mdmlocalmanagement.lib", "mdmregistration.lib", "mgmtapi.lib", "mi.lib", "mmdevapi.lib", "mpr.lib", "mprapi.lib", "mqrt.lib", "mrmsupport.lib", "msacm32.lib", "msajapi.lib", "mscms.lib", "mscoree.lib", "msctfmonitor.lib", "msdelta.lib", "msdmo.lib", "msdrm.lib", "msi.lib", "msimg32.lib", "mspatcha.lib", "mspatchc.lib", "msports.lib", "msrating.lib", "mssign32.lib", "mstask.lib", "msvfw32.lib", "mswsock.lib", "mtxdm.lib", "ncrypt.lib", "ndfapi.lib", "ndis.lib", "netapi32.lib", "netsh.lib", "netshell.lib", "newdev.lib", "ninput.lib", "normaliz.lib", "ntdll.lib", "ntdllk.lib", "ntdsapi.lib", "ntlanman.lib", "ntoskrnl.lib", "odbc32.lib", "odbcbcp.lib", "offreg.lib", "oleacc.lib", "oleaut32.lib", "oledlg.lib", "ondemandconnroutehelper.lib", "opengl32.lib", "p2p.lib", "p2pgraph.lib", "pdh.lib", "peerdist.lib", "powrprof.lib", "prntvpt.lib", "projectedfslib.lib", "propsys.lib", "psapi.lib", "pshed.lib", "query.lib", "qwave.lib", "rasapi32.lib", "rasdlg.lib", "resutils.lib", "rpcns4.lib", "rpcproxy.lib", "rpcrt4.lib", "rstrtmgr.lib", "rtm.lib", "rtutils.lib", "rtworkq.lib", "sas.lib", "scarddlg.lib", "schannel.lib", "sechost.lib", "secur32.lib", "sensapi.lib", "sensorsutilsv2.lib", "setupapi.lib", "sfc.lib", "shdocvw.lib", "shell32.lib", "shlwapi.lib", "slc.lib", "slcext.lib", "slwga.lib", "snmpapi.lib", "spoolss.lib", "srclient.lib", "srpapi.lib", "sspicli.lib", "sti.lib", "t2embed.lib", "tapi32.lib", "tbs.lib", "tdh.lib", "tokenbinding.lib", "traffic.lib", "txfw32.lib", "ualapi.lib", "uiautomationcore.lib", "urlmon.lib", "user32.lib", "userenv.lib", "usp10.lib", "uxtheme.lib", "verifier.lib", "version.lib", "vertdll.lib", "vhfum.lib", "virtdisk.lib", "vmdevicehost.lib", "vmsavedstatedumpprovider.lib", "wcmapi.lib", "wdsbp.lib", "wdsclientapi.lib", "wdsmc.lib", "wdspxe.lib", "wdstptc.lib", "webauthn.lib", "webservices.lib", "websocket.lib", "wecapi.lib", "wer.lib", "wevtapi.lib", "winbio.lib", "windows.media.mediacontrol.lib", "windows.networking.lib", "windows.ui.lib", "windowscodecs.lib", "winfax.lib", "winhttp.lib", "winhvemulation.lib", "winhvplatform.lib", "wininet.lib", "winmm.lib", "winscard.lib", "winspool.lib", "wintrust.lib", "winusb.lib", "wlanapi.lib", "wlanui.lib", "wldap32.lib", "wldp.lib", "wmvcore.lib", "wnvapi.lib", "wofutil.lib", "ws2_32.lib", "wscapi.lib", "wsclient.lib", "wsdapi.lib", "wsmsvc.lib", "wsnmp32.lib", "wtsapi32.lib", "xinput1_4.lib", "xolehlp.lib"] },
	}

import Program
import Elem
import Action
import Event
import Gui
import Files
import Timer
import Http
import Sqlite
import InternalFiles
import Clipboard
import Tcp
import Process
import Audio
import Device
import SystemMonitor
import ImageData
import Assets
import Host

gui_init! : () => {}
gui_init! = || Program.start!(main)

gui_dispatch! : Box((U64 => {})), U64 => {}
gui_dispatch! = |dispatch_box, event_id| Box.unbox(dispatch_box)(event_id)

gui_complete! : Box((Box((Box(state) -> Box(Action.Action(state)))) => {})), Box((Box(state) -> Box(Action.Action(state)))) => {}
gui_complete! = |dispatch_box, completion_box| Box.unbox(dispatch_box)(completion_box)

gui_run_task! : Box((() => Box((Box(state) -> Box(Action.Action(state)))))) => Box((Box(state) -> Box(Action.Action(state))))
gui_run_task! = |task_box| Box.unbox(task_box)()
