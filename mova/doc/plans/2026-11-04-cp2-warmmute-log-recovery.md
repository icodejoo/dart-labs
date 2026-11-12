# CP2 Q13 同次运行日志恢复

原run-id `cp2-warmmute-resume-20261104-183712`；设备进程14351，真实 AUTORUN DONE 于18:42:39。adb重启后从设备logcat缓冲补取全部15条原页VERDICT，不增加真机轮次。原主机结果保留，没有改写。

原页结果：`{'PASS': 5, 'FAIL': 10}`。正式CP2加严结果：`{'BLOCKED': 15}`。

系统音量只有原11条采样加恢复完成后的1条，共12/16，不足门禁；所有已采值为0。不得用当前重复读数补造历史采样，故正式15条均BLOCKED，不能称5条CP2 PASS。原页Q13B/C的10条FAIL保留为夹具资源污染线索。

原始恢复日志 `example\tool\coverage_evidence\cp2-warmmute-adb-recovered-1842.log`；SHA-256 `0dde555ca272c0e153e9b2ace4f898212ef2df5ac86c3d48b6cdc7395f66d232`；派生记录 `example\tool\coverage_evidence\matrix-cp2-warmmute-resume-20261104-183712\matrix-cp2-warmmute-resume-20261104-183712-cp2-warmmute.recovered.json`。B/C期间有SL_RESULT_MEMORY_FAILURE，旧页未移交注入内核所有权，源码修复未进入原APK。
