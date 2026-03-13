import 'package:flutter/material.dart';
import 'package:flutter_layout_grid/flutter_layout_grid.dart';

void main() {
  runApp(const ReorderableGridApp());
}

class ReorderableGridApp extends StatelessWidget {
  const ReorderableGridApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Reorderable Grid Example',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const ReorderableGridPage(),
    );
  }
}

class ReorderableGridPage extends StatefulWidget {
  const ReorderableGridPage({super.key});

  @override
  State<ReorderableGridPage> createState() => _ReorderableGridPageState();
}

class _ReorderableGridPageState extends State<ReorderableGridPage> {
  final List<int> _items = List<int>.generate(20, (int index) => index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LayoutGrid Performance Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'High Performance Integration',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'This example demonstrates ReorderableListView inside a LayoutGrid with addRepaintBoundary: true for smooth 60+ FPS.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              LayoutGrid(
                columnSizes: [1.fr, 1.fr],
                rowSizes: [auto, auto],
                rowGap: 16,
                columnGap: 16,
                children: [
                  // Column 1: A static grid section
                  // Wrapping in RepaintBoundary to isolate repaints
                  _buildStaticSection('Statistics', Colors.blue)
                      .withGridPlacement(
                    columnStart: 0,
                    rowStart: 0,
                    addRepaintBoundary: true,
                  ),

                  // Column 2: Reorderable List
                  // ReorderableListView is already a heavy widget, isolation helps
                  _buildReorderableSection().withGridPlacement(
                    columnStart: 1,
                    rowStart: 0,
                    addRepaintBoundary: true,
                  ),

                  // Bottom section spanning both columns
                  _buildStaticSection('Footer Info', Colors.green)
                      .withGridPlacement(
                    columnStart: 0,
                    columnSpan: 2,
                    rowStart: 1,
                    addRepaintBoundary: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStaticSection(String title, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics, color: color),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'This section is isolated by a RepaintBoundary. '
            'Changes in the reorderable list will not trigger repaints here.',
            style: TextStyle(color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(int itemValue, {bool isDragging = false}) {
    return ListTile(
      key: ValueKey('item_$itemValue'),
      tileColor: isDragging
          ? Colors.deepPurple[100]
          : (itemValue.isOdd
              ? Colors.white
              : Colors.deepPurple[50]?.withOpacity(0.3)),
      title: Text('Performance Item $itemValue'),
      subtitle: const Text('Try dragging me!'),
      leading: const CircleAvatar(
        child: Icon(Icons.flash_on, size: 16),
      ),
      trailing: const Icon(Icons.drag_handle),
    );
  }

  Widget _buildReorderableSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.deepPurple.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurple.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(Icons.reorder, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text('Task Reordering',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // ReorderableListView now works DIRECTLY in LayoutGrid auto tracks!
          // No hardcoded height, no itemCount * 72.0 hacks.
          // The package now automatically performs a layout fallback to find the correct size.
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              for (int index = 0; index < _items.length; index++)
                _buildTile(_items[index]),
            ],
            onReorder: (int oldIndex, int newIndex) {
              setState(() {
                if (oldIndex < newIndex) {
                  newIndex -= 1;
                }
                final int item = _items.removeAt(oldIndex);
                _items.insert(newIndex, item);
              });
            },
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
