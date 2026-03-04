import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'employee_view.dart';
import 'main.dart';

class AdminDashboard extends StatefulWidget {
  final Map<String, dynamic> adminData;
  const AdminDashboard({super.key, required this.adminData});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late final StreamSubscription<QuerySnapshot> _tasksSubscription;
  final Set<String> _notifiedCompletedTasks = {};
  List<Map<String, dynamic>> _teamMembers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTeam();
    _setupRealtimeListener();
  }

  Future<void> _loadTeam() async {
    setState(() => _isLoading = true);
    final adminId = widget.adminData['id'];
    
    final memberships = await FirebaseFirestore.instance
        .collection('team_memberships')
        .where('admin_id', isEqualTo: adminId)
        .get();

    final profileFutures = memberships.docs.map((doc) => 
        FirebaseFirestore.instance.collection('profiles').doc(doc['employee_id']).get()
    );
    
    final profileSnapshots = await Future.wait(profileFutures);
    List<Map<String, dynamic>> loadedTeam = [];

    for (var empProfile in profileSnapshots) {
      if (empProfile.exists) {
        loadedTeam.add({
          'id': empProfile.id,
          'display_name': empProfile.data()?['display_name'] ?? 'Unknown'
        });
      }
    }

    if (mounted) {
      setState(() {
        _teamMembers = loadedTeam;
        _isLoading = false;
      });
    }
  }

  void _setupRealtimeListener() {
    _tasksSubscription = FirebaseFirestore.instance
        .collection('tasks')
        .where('admin_id', isEqualTo: widget.adminData['id'])
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final data = change.doc.data() as Map<String, dynamic>;
          final taskId = change.doc.id;
          
          if (data['is_done'] == true && !_notifiedCompletedTasks.contains(taskId)) {
            _notifiedCompletedTasks.add(taskId);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF172B4D),
                  duration: const Duration(seconds: 4),
                  content: Text('TASK DONE: ${data['title']}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              );
            }
          } else if (data['is_done'] == false) {
            _notifiedCompletedTasks.remove(taskId);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _tasksSubscription.cancel();
    super.dispose();
  }

  void _showAddEmployeeDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (dialogContext) {
        return _AddEmployeeSheet(
          adminId: widget.adminData['id'],
          currentTeam: _teamMembers,
          onAdded: _loadTeam,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MY WORKSPACE', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -1)),
        leading: IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0052CC)))
          : _teamMembers.isEmpty
              ? const Center(child: Text('No employees in your workspace yet.', style: TextStyle(fontSize: 20, color: Color(0xFF7A869A))))
              : ListView.builder(
                  itemCount: _teamMembers.length,
                  itemBuilder: (context, index) {
                    final employee = _teamMembers[index];
                    return InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => EmployeeTaskView(
                          employeeId: employee['id'],
                          employeeName: employee['display_name'],
                          isAdmin: true,
                          currentUserId: widget.adminData['id'],
                          currentUserName: widget.adminData['display_name'],
                          workspaceAdminId: null,
                        ),
                      )),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(bottom: BorderSide(color: Color(0xFFDFE1E6)))
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(employee['display_name'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF172B4D))),
                            const Icon(Icons.arrow_forward_ios, color: Color(0xFF172B4D), size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddEmployeeDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Employee', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _AddEmployeeSheet extends StatefulWidget {
  final String adminId;
  final List<Map<String, dynamic>> currentTeam;
  final VoidCallback onAdded;

  const _AddEmployeeSheet({required this.adminId, required this.currentTeam, required this.onAdded});

  @override
  State<_AddEmployeeSheet> createState() => _AddEmployeeSheetState();
}

class _AddEmployeeSheetState extends State<_AddEmployeeSheet> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _allAvailableEmployees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAvailableEmployees();
  }

  Future<void> _loadAvailableEmployees() async {
    final response = await FirebaseFirestore.instance.collection('profiles').where('role', isEqualTo: 'employee').get();
    final currentTeamIds = widget.currentTeam.map((e) => e['id']).toSet();
    final available = response.docs.where((doc) => !currentTeamIds.contains(doc.id)).map((doc) => {'id': doc.id, ...doc.data()}).toList();

    if (mounted) {
      setState(() {
        _allAvailableEmployees = available;
        _filteredEmployees = available;
        _isLoading = false;
      });
    }
  }

  void _filterResults(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredEmployees = _allAvailableEmployees;
      } else {
        _filteredEmployees = _allAvailableEmployees.where((emp) => emp['display_name'].toString().toLowerCase().contains(query.toLowerCase())).toList();
      }
    });
  }

  Future<void> _processAdd(String username) async {
    if (username.isEmpty) return;
    final existingMatch = _allAvailableEmployees.where((e) => e['display_name'].toString().toLowerCase() == username.toLowerCase()).toList();

    if (existingMatch.isNotEmpty) {
      await _linkEmployee(existingMatch.first['id']);
    } else {
      _showCreateConfirmation(username);
    }
  }

  Future<void> _linkEmployee(String employeeId) async {
    final docId = '${widget.adminId}_$employeeId';
    await FirebaseFirestore.instance.collection('team_memberships').doc(docId).set({'admin_id': widget.adminId, 'employee_id': employeeId});
    if (mounted) { Navigator.pop(context); widget.onAdded(); }
  }

  void _showCreateConfirmation(String username) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('New Employee?', style: TextStyle(color: Color(0xFF172B4D), fontWeight: FontWeight.bold)),
        content: Text('The username "$username" does not exist in the system. Would you like to create a brand new account for them?', style: const TextStyle(color: Color(0xFF7A869A))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final newEmp = await FirebaseFirestore.instance.collection('profiles').add({'display_name': username, 'role': 'employee'});
                await _linkEmployee(newEmp.id);
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error creating employee. Username may be taken.')));
              }
            },
            child: const Text('CREATE & ADD'),
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Add to Your Team', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF172B4D))),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            cursorColor: const Color(0xFF0052CC),
            style: const TextStyle(color: Color(0xFF172B4D), fontSize: 18),
            decoration: InputDecoration(
              hintText: 'Search existing or type new...',
              hintStyle: const TextStyle(color: Color(0xFF7A869A)),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF7A869A)),
              filled: true,
              fillColor: const Color(0xFFF4F5F7),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onChanged: _filterResults,
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Color(0xFF0052CC)))
          else if (_filteredEmployees.isNotEmpty)
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredEmployees.length,
                itemBuilder: (context, index) {
                  final emp = _filteredEmployees[index];
                  return ListTile(
                    title: Text(emp['display_name'], style: const TextStyle(color: Color(0xFF172B4D), fontSize: 18, fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.add_circle_outline, color: Color(0xFF0052CC)),
                    onTap: () { _controller.text = emp['display_name']; _processAdd(emp['display_name']); },
                  );
                },
              ),
            )
          else if (_controller.text.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Text('No existing employee matches. Click below to create as new.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF7A869A), fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: () => _processAdd(_controller.text.trim()),
            child: const Text('ADD TO WORKSPACE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}