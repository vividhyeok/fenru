import 'package:flutter/material.dart';
Future<String?> askText(BuildContext context, String title, {String initial = '', bool multiline = false}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(context: context, builder: (context) => AlertDialog(
    title: Text(title), content: SizedBox(width: 480, child: TextField(
      controller: controller, autofocus: true, minLines: multiline ? 4 : 1,
      maxLines: multiline ? 12 : 1, onSubmitted: multiline ? null : (value) => Navigator.pop(context, value),
      decoration: const InputDecoration(hintText: '내용 입력'))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
      FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('저장'))]));
  controller.dispose();
  return result;
}
Future<bool> confirm(BuildContext context, String title, String body) async =>
  await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(title),
    content: Text(body), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('계속'))])) ?? false;

