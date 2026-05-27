import 'package:flutter/material.dart';
import 'package:sborapps/core/services/admin_auth_service.dart';
import 'ui/screens/orders_screen.dart';
import 'ui/screens/history_screen.dart';
import 'ui/screens/profile_screen.dart';
import 'ui/drawer/admin_login_screen.dart';
import 'ui/drawer/picker_drawer.dart';

class OrderPickerApp extends StatefulWidget {
  const OrderPickerApp({Key? key}) : super(key: key);

  @override
  State<OrderPickerApp> createState() => _OrderPickerAppState();
}

class _OrderPickerAppState extends State<OrderPickerApp> {
  bool _isAuthenticated = false;
  bool _isCheckingAuth = true;
  Admin? _currentAdmin;

  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    try {
      final isAuth = await AdminAuthService.isAuthenticated();
      final admin = await AdminAuthService.getSavedAdmin();

      setState(() {
        _isAuthenticated = isAuth;
        _currentAdmin = admin;
        _isCheckingAuth = false;
      });
    } catch (e) {
      print('Auth check error: $e');
      setState(() {
        _isAuthenticated = false;
        _isCheckingAuth = false;
      });
    }
  }

  void _handleLoginSuccess(Admin admin) {
    setState(() {
      _isAuthenticated = true;
      _currentAdmin = admin;
    });
  }

  void _handleLogout() {
    setState(() {
      _isAuthenticated = false;
      _currentAdmin = null;
    });
    _checkAuthentication();
  }

  @override
  Widget build(BuildContext context) {
    // Загрузка авторизации
    if (_isCheckingAuth) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Сборка заказов',
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Загрузка...'),
              ],
            ),
          ),
        ),
      );
    }

    // Если не авторизован - показать экран входа
    if (!_isAuthenticated) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Сборка заказов',
        theme: ThemeData(primarySwatch: Colors.blue),
        home: AdminLoginScreen(
          onLoginSuccess: _handleLoginSuccess,
        ),
      );
    }

    // Авторизован - показать приложение
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Сборка заказов',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MainScaffold(
        admin: _currentAdmin,
        onLogout: _handleLogout,
      ),
      routes: {
        '/profile': (context) => const ProfileScreen(),
      },
    );
  }
}

class MainScaffold extends StatefulWidget {
  final Admin? admin;
  final VoidCallback onLogout;

  const MainScaffold({
    Key? key,
    this.admin,
    required this.onLogout,
  }) : super(key: key);

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;
  String pickerName = 'Сборщик заказов';

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
        onProfileTap: () {
          Navigator.pop(context);
          Navigator.of(context).pushNamed('/profile');
        },
      ),
      appBar: AppBar(
        title: Text(
          _selectedIndex == 0 ? 'Заказы' : 'История',
          style: const TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: Colors.blue[600],
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          onTap: (index) => setState(() => _selectedIndex = index),
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: 'Заказы'),
            Tab(icon: Icon(Icons.history), text: 'История'),
          ],
        ),
        actions: [
          // ✅ Кнопка профиля в AppBar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).pushNamed('/profile');
                },
                child: Tooltip(
                  message: widget.admin?.fullName ?? 'Профиль',
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white.withOpacity(0.3),
                    child: Icon(
                      Icons.admin_panel_settings,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
