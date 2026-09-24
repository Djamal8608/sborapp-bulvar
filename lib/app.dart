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
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Адаптивные параметры на основе высоты экрана
    final isVerySmallHeight = screenHeight < 500;
    final isCompactHeight = screenHeight < 600;
    final isNarrowWidth = screenWidth < 360;

    // Адаптивные размеры
    final appBarTitleSize = isVerySmallHeight ? 16.0 : 18.0;
    final avatarRadius = isVerySmallHeight ? 14.0 : 18.0;
    final iconSize = isVerySmallHeight ? 18.0 : 20.0;
    final tabIconSize = isVerySmallHeight ? 18.0 : 24.0;
    final tabFontSize = isVerySmallHeight ? 10.0 : 14.0;

    // Показывать текст в табах только если достаточно места
    final showTabText = !isVerySmallHeight && !isNarrowWidth;

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
      appBar: PreferredSize(
        // Адаптивная высота AppBar
        preferredSize: Size.fromHeight(
            kToolbarHeight +
                (isVerySmallHeight ? 36.0 : 48.0) + // Высота TabBar
                (isCompactHeight ? 0.0 : 4.0) // Дополнительный padding
        ),
        child: Container(
          color: Colors.blue[600],
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Верхняя часть AppBar с заголовком и аватаром
                SizedBox(
                  height: isCompactHeight ? 44.0 : 56.0,
                  child: Row(
                    children: [
                      // Кнопка меню (Drawer)
                      IconButton(
                        icon: Icon(
                          Icons.menu,
                          color: Colors.white,
                          size: iconSize,
                        ),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),

                      // Заголовок
                      Expanded(
                        child: Center(
                          child: Text(
                            _selectedIndex == 0 ? 'Заказы' : 'История',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: appBarTitleSize,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                      // Кнопка профиля
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isVerySmallHeight ? 4.0 : 8.0,
                        ),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).pushNamed('/profile');
                          },
                          child: Tooltip(
                            message: widget.admin?.fullName ?? 'Профиль',
                            child: CircleAvatar(
                              radius: avatarRadius,
                              backgroundColor: Colors.white.withOpacity(0.3),
                              child: Icon(
                                Icons.admin_panel_settings,
                                size: isVerySmallHeight ? 16.0 : 20.0,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // TabBar - адаптивный размер
                SizedBox(
                  height: isVerySmallHeight ? 36.0 : 48.0,
                  child: TabBar(
                    controller: _tabController,
                    onTap: (index) => setState(() => _selectedIndex = index),
                    indicatorColor: Colors.white,
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelPadding: EdgeInsets.zero,
                    tabs: [
                      Tab(
                        icon: Icon(Icons.list_alt, size: tabIconSize),
                        text: showTabText ? 'Заказы' : null,
                      ),
                      Tab(
                        icon: Icon(Icons.history, size: tabIconSize),
                        text: showTabText ? 'История' : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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