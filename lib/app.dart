import 'package:flutter/material.dart';
import 'ui/screens/orders_screen.dart';
import 'ui/screens/history_screen.dart';
import 'ui/screens/profile_screen.dart';
import 'ui/drawer/picker_drawer.dart';

class OrderPickerApp extends StatelessWidget {
  const OrderPickerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Сборка заказов',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MainScaffold(),
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({Key? key}) : super(key: key);

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;
  String pickerName = 'Сборщик';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: PickerDrawer(
        pickerName: pickerName,
        onNameChanged: (name) {
          setState(() {
            pickerName = name;
          });
        },
        onOrdersTap: () => _switchToTab(0),
        onHistoryTap: () => _switchToTab(1),
      ),
      appBar: AppBar(
        title: Text(_selectedIndex == 0 ? 'Заказы' : 'История'),
        bottom: TabBar(
          controller: _tabController,
          onTap: (index) => setState(() => _selectedIndex = index),
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: 'Заказы'),
            Tab(icon: Icon(Icons.history), text: 'История'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          OrdersScreen(),
          HistoryScreen(),
        ],
      ),
    );
  }

  void _switchToTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _tabController.animateTo(index);
    Navigator.pop(context);
  }
}
