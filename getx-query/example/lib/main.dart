import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:getx_query/getx_query.dart';
import 'demo_shell.dart';

void main() {
  runApp(const GetxQueryDemoApp());
}

class GetxQueryDemoApp extends StatelessWidget {
  const GetxQueryDemoApp({super.key});
  @override
  Widget build(BuildContext context) => GetMaterialApp(
        title: 'getx_query demo',
        theme: ThemeData(colorSchemeSeed: Colors.orange, useMaterial3: true),
        initialBinding: BindingsBuilder(() {
          Get.put(QueryService());
        }),
        home: const DemoShell(),
      );
}
