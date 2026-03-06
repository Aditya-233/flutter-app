import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';

class EmployeeTaskView extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final bool isAdmin;

  final String currentUserId;
  final String currentUserName;
  final String? workspaceAdminId;

  const EmployeeTaskView({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.isAdmin,
    required this.currentUserId,
    required this.currentUserName,
    this.workspaceAdminId,
  });

  @override
  State<EmployeeTaskView> createState() => _EmployeeTaskViewState();
}

class _EmployeeTaskViewState extends State<EmployeeTaskView> {
  Map<String, String> _adminNames = {};
  bool _filterImportant = false; // Toggles the "Important Only" view

  @override
  void initState() {
    super.initState();
    _fetchAllAdminNames();
  }

  Future<void> _fetchAllAdminNames() async {
    final profiles = await FirebaseFirestore.instance
        .collection('profiles')
        .where('role', isEqualTo: 'admin')
        .get();
    Map<String, String> map = {};
    for (var doc in profiles.docs) {
      map[doc.id] = doc['display_name'];
    }
    if (mounted) setState(() => _adminNames = map);
  }

  void _showAddProjectDialog(BuildContext context) {
    final TextEditingController projectController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'New Folder/Project',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF172B4D),
          ),
        ),
        content: TextField(
          controller: projectController,
          autofocus: true,
          cursorColor: const Color(0xFF0052CC),
          style: const TextStyle(color: Color(0xFF172B4D)),
          decoration: const InputDecoration(
            hintText: 'e.g. Website Redesign',
            hintStyle: TextStyle(color: Color(0xFF7A869A)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (projectController.text.trim().isNotEmpty) {
                await FirebaseFirestore.instance.collection('projects').add({
                  'title': projectController.text.trim(),
                  'employee_id': widget.employeeId,
                  'admin_id': widget.currentUserId,
                  'created_at': FieldValue.serverTimestamp(),
                });
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              }
            },
            child: const Text('CREATE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isAdmin ? "${widget.employeeName}'s Folders" : "My Tasks",
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: -1,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _filterImportant ? Icons.star : Icons.star_border,
              color: _filterImportant ? Colors.amber : Colors.white,
            ),
            tooltip: 'Show Important Only',
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _filterImportant = !_filterImportant);
            },
          ),
          if (widget.isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => _showAddProjectDialog(context),
                icon: const Icon(Icons.create_new_folder),
                label: const Text(
                  'New Customer',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          if (!widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('projects')
            .where('employee_id', isEqualTo: widget.employeeId)
            .snapshots(),
        builder: (context, projectSnapshot) {
          if (!projectSnapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF0052CC)),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('tasks')
                .where('employee_id', isEqualTo: widget.employeeId)
                .snapshots(),
            builder: (context, taskSnapshot) {
              if (!taskSnapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF0052CC)),
                );
              }

              final projects = projectSnapshot.data!.docs.map((d) {
                final map = d.data() as Map<String, dynamic>;
                map['id'] = d.id;
                return map;
              }).toList();

              // Sort alphabetically by title
              projects.sort((a, b) {
                final titleA = (a['title'] ?? '').toString().toLowerCase();
                final titleB = (b['title'] ?? '').toString().toLowerCase();
                return titleA.compareTo(titleB);
              });

              final allTasks = taskSnapshot.data!.docs.map((d) {
                final map = d.data() as Map<String, dynamic>;
                map['id'] = d.id;
                return map;
              }).toList();

              // Filter out projects if we are in "Important Only" view and the project has zero important tasks
              var filteredProjects = projects;
              if (_filterImportant) {
                filteredProjects = projects.where((p) {
                  return allTasks.any(
                    (t) =>
                        t['project_id'] == p['id'] && t['is_important'] == true,
                  );
                }).toList();
              }

              if (filteredProjects.isEmpty) {
                return Center(
                  child: Text(
                    _filterImportant
                        ? 'No important tasks found.'
                        : (widget.isAdmin
                              ? 'No projects assigned to this employee yet.'
                              : 'No active projects.'),
                    style: const TextStyle(
                      fontSize: 18,
                      color: Color(0xFF7A869A),
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: filteredProjects.length,
                itemBuilder: (context, index) {
                  final p = filteredProjects[index];
                  final adminName =
                      _adminNames[p['admin_id']] ?? 'Unknown Admin';

                  var projectTasks = allTasks
                      .where((t) => t['project_id'] == p['id'])
                      .toList();

                  // If filter is on, only show the important tasks within this project
                  if (_filterImportant) {
                    projectTasks = projectTasks
                        .where((t) => t['is_important'] == true)
                        .toList();
                  }

                  // Sorting: Important tasks first, then by created_at date
                  projectTasks.sort((a, b) {
                    final bool aImportant = a['is_important'] == true;
                    final bool bImportant = b['is_important'] == true;

                    if (aImportant && !bImportant) return -1;
                    if (!aImportant && bImportant) return 1;

                    return (a['created_at']?.compareTo(b['created_at']) ?? 0);
                  });

                  return ProjectAccordion(
                    key: ValueKey(p['id']),
                    project: p,
                    projectTasks: projectTasks,
                    isAdmin: widget.isAdmin,
                    currentUserId: widget.currentUserId,
                    currentUserName: widget.currentUserName,
                    employeeId: widget.employeeId,
                    adminName: adminName,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class ProjectAccordion extends StatefulWidget {
  final Map<String, dynamic> project;
  final List<Map<String, dynamic>> projectTasks;
  final bool isAdmin;
  final String currentUserId;
  final String currentUserName;
  final String employeeId;
  final String adminName;

  const ProjectAccordion({
    super.key,
    required this.project,
    required this.projectTasks,
    required this.isAdmin,
    required this.currentUserId,
    required this.currentUserName,
    required this.employeeId,
    required this.adminName,
  });

  @override
  State<ProjectAccordion> createState() => _ProjectAccordionState();
}

class _ProjectAccordionState extends State<ProjectAccordion> {
  void _deleteProject() async {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Delete Folder?',
          style: TextStyle(
            color: Color(0xFF172B4D),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'This will permanently delete all tasks inside this folder.',
          style: TextStyle(color: Color(0xFF7A869A)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('projects')
                  .doc(widget.project['id'])
                  .delete();
              final tasksRes = await FirebaseFirestore.instance
                  .collection('tasks')
                  .where('project_id', isEqualTo: widget.project['id'])
                  .get();
              final batch = FirebaseFirestore.instance.batch();
              for (var doc in tasksRes.docs) {
                batch.delete(doc.reference);
              }
              await batch.commit();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  void _clearCompletedTasks() async {
    HapticFeedback.vibrate();
    final res = await FirebaseFirestore.instance
        .collection('tasks')
        .where('project_id', isEqualTo: widget.project['id'])
        .where('is_done', isEqualTo: true)
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (var doc in res.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  void _showAddTaskDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => _MultiSelectTaskDialog(
        projectId: widget.project['id'],
        adminId: widget.project['admin_id'],
        employeeId: widget.employeeId,
        currentUserName: widget.currentUserName,
      ),
    );
  }

  void _editDescription(Map<String, dynamic> task) {
    final TextEditingController descController = TextEditingController(
      text: task['description'] ?? '',
    );
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Edit Description',
          style: TextStyle(
            color: Color(0xFF172B4D),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: descController,
          cursorColor: const Color(0xFF0052CC),
          style: const TextStyle(color: Color(0xFF172B4D)),
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter 1-2 lines...',
            hintStyle: TextStyle(color: Color(0xFF7A869A)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('tasks')
                  .doc(task['id'])
                  .update({'description': descController.text.trim()});
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    switch (day % 10) {
      case 1:
        return '${day}st';
      case 2:
        return '${day}nd';
      case 3:
        return '${day}rd';
      default:
        return '${day}th';
    }
  }

  void _updateDate(Map<String, dynamic> task) async {
    final current = task['deadline_date'] != null
        ? DateTime.parse(task['deadline_date'])
        : DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF0052CC)),
        ),
        child: child!,
      ),
    );

    if (selected != null) {
      final dateStr =
          '${selected.year}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';

      final now = DateTime.now();
      final todayStr = '${_getMonthName(now.month)} ${_getDaySuffix(now.day)}';
      final historyEntry =
          'Changed by ${widget.currentUserName} to $dateStr on $todayStr';

      await FirebaseFirestore.instance
          .collection('tasks')
          .doc(task['id'])
          .update({
            'deadline_date': dateStr,
            'deadline_history': FieldValue.arrayUnion([historyEntry]),
          });
    }
  }

  void _showHistoryPopup(List<dynamic>? history) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Deadline History',
          style: TextStyle(
            color: Color(0xFF172B4D),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: history == null || history.isEmpty
              ? const Text(
                  'No changes made yet.',
                  style: TextStyle(color: Color(0xFF7A869A)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: history.length,
                  itemBuilder: (c, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Text(
                      '• ${history[i]}',
                      style: const TextStyle(
                        color: Color(0xFF172B4D),
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final bool isReadOnly =
        widget.isAdmin && widget.project['admin_id'] != widget.currentUserId;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDFE1E6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true, // Auto-expand to show priority items easily
          iconColor: const Color(0xFF172B4D),
          collapsedIconColor: const Color(0xFF172B4D),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          controlAffinity: ListTileControlAffinity.leading,
          title: RichText(
            text: TextSpan(
              text: widget.project['title'],
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF172B4D),
              ),
              children: [
                TextSpan(
                  text: ' (by ${widget.adminName})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    color: Color(0xFF7A869A),
                  ),
                ),
              ],
            ),
          ),
          trailing: (!isReadOnly && widget.isAdmin)
              ? IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  onPressed: _deleteProject,
                )
              : null,
          children: [
            if (!isReadOnly)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _showAddTaskDialog(context),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Task'),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _clearCompletedTasks,
                      icon: const Icon(Icons.cleaning_services, size: 16),
                      label: const Text('Clear Done'),
                    ),
                  ],
                ),
              ),

            if (widget.projectTasks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'No tasks yet.',
                  style: TextStyle(
                    color: Color(0xFF7A869A),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              Column(
                children: widget.projectTasks.map((task) {
                  final isDone = task['is_done'] == true;
                  final isImportant = task['is_important'] == true;
                  final hasDescription =
                      task['description'] != null &&
                      task['description'].toString().isNotEmpty;
                  final hasHistory =
                      task['deadline_history'] != null &&
                      (task['deadline_history'] as List).isNotEmpty;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                isDone
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 28,
                                color: isDone
                                    ? const Color(0xFF36B37E)
                                    : const Color(0xFF172B4D),
                              ),
                              onPressed: isReadOnly
                                  ? null
                                  : () async {
                                      if (isDone) {
                                        HapticFeedback.lightImpact();
                                      } else {
                                        HapticFeedback.heavyImpact();
                                      }
                                      await FirebaseFirestore.instance
                                          .collection('tasks')
                                          .doc(task['id'])
                                          .update({'is_done': !isDone});
                                    },
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                task['title'],
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: isDone
                                      ? FontWeight.normal
                                      : FontWeight.w600,
                                  color: isDone
                                      ? const Color(0xFF7A869A)
                                      : const Color(0xFF172B4D),
                                  decoration: isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),

                            // Important Toggle Button
                            IconButton(
                              padding: const EdgeInsets.only(right: 8),
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                isImportant ? Icons.star : Icons.star_border,
                                color: isImportant
                                    ? Colors.amber
                                    : const Color(0xFFDFE1E6),
                                size: 24,
                              ),
                              onPressed: isReadOnly
                                  ? null
                                  : () async {
                                      HapticFeedback.selectionClick();
                                      await FirebaseFirestore.instance
                                          .collection('tasks')
                                          .doc(task['id'])
                                          .update({
                                            'is_important': !isImportant,
                                          });
                                    },
                            ),

                            if (hasHistory)
                              IconButton(
                                padding: const EdgeInsets.only(right: 8),
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.history,
                                  color: Color(0xFF7A869A),
                                  size: 20,
                                ),
                                onPressed: () =>
                                    _showHistoryPopup(task['deadline_history']),
                              ),
                            InkWell(
                              onTap: isReadOnly
                                  ? null
                                  : () => _updateDate(task),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isDone
                                      ? const Color(0xFFF4F5F7)
                                      : const Color(0xFFE6F0FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  task['deadline_date'] != null
                                      ? _formatDate(task['deadline_date'])
                                      : 'Set Date',
                                  style: TextStyle(
                                    color: isDone
                                        ? const Color(0xFF7A869A)
                                        : const Color(0xFF0052CC),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (hasDescription || (!isReadOnly && widget.isAdmin))
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 40.0,
                              top: 4.0,
                              bottom: 8.0,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    hasDescription
                                        ? 'Note: ${task['description']}'
                                        : 'No description',
                                    style: TextStyle(
                                      color: const Color(0xFF7A869A),
                                      fontSize: 14,
                                      fontStyle: hasDescription
                                          ? FontStyle.normal
                                          : FontStyle.italic,
                                    ),
                                  ),
                                ),
                                if (!isReadOnly && widget.isAdmin)
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(
                                      Icons.edit,
                                      size: 16,
                                      color: Color(0xFF7A869A),
                                    ),
                                    onPressed: () => _editDescription(task),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _MultiSelectTaskDialog extends StatefulWidget {
  final String projectId;
  final String adminId;
  final String employeeId;
  final String currentUserName;
  const _MultiSelectTaskDialog({
    required this.projectId,
    required this.adminId,
    required this.employeeId,
    required this.currentUserName,
  });

  @override
  State<_MultiSelectTaskDialog> createState() => _MultiSelectTaskDialogState();
}

class _MultiSelectTaskDialogState extends State<_MultiSelectTaskDialog> {
  final List<String> _allTasks = [
    'Payment collection',
    'Document collection',
    'Showroom visit',
    'Bank work',
    'Loan work',
    'Agro delivery',
    'Biometric',
    'Implement work',
    'Old tractor work',
    'Other work',
  ];
  String _searchQuery = '';

  // Updated Map to include 'important' status
  final Map<String, Map<String, dynamic>> _selectedTaskDetails = {};
  bool _isSubmitting = false;

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    switch (day % 10) {
      case 1:
        return '${day}st';
      case 2:
        return '${day}nd';
      case 3:
        return '${day}rd';
      default:
        return '${day}th';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredTasks = _allTasks
        .where(
          (task) => task.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();

    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text(
        'Add Tasks',
        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF172B4D)),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              cursorColor: const Color(0xFF0052CC),
              style: const TextStyle(color: Color(0xFF172B4D)),
              decoration: const InputDecoration(
                hintText: 'Search predefined tasks...',
                hintStyle: TextStyle(color: Color(0xFF7A869A)),
                prefixIcon: Icon(Icons.search, color: Color(0xFF7A869A)),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFDFE1E6)),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF4C9AFF)),
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: filteredTasks.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'No matching tasks found.',
                        style: TextStyle(color: Color(0xFF7A869A)),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredTasks.length,
                      itemBuilder: (context, index) {
                        final task = filteredTasks[index];
                        final isSelected = _selectedTaskDetails.containsKey(
                          task,
                        );

                        return Column(
                          children: [
                            CheckboxListTile(
                              title: Text(
                                task,
                                style: const TextStyle(
                                  color: Color(0xFF172B4D),
                                  fontSize: 16,
                                ),
                              ),
                              value: isSelected,
                              activeColor: const Color(0xFF0052CC),
                              checkColor: Colors.white,
                              onChanged: (bool? checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedTaskDetails[task] = {
                                      'desc': '',
                                      'date': null,
                                      'important': false,
                                    };
                                  } else {
                                    _selectedTaskDetails.remove(task);
                                  }
                                });
                              },
                            ),
                            if (isSelected)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 40,
                                  right: 16,
                                  bottom: 16,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    TextField(
                                      cursorColor: const Color(0xFF0052CC),
                                      style: const TextStyle(
                                        color: Color(0xFF172B4D),
                                        fontSize: 14,
                                      ),
                                      decoration: const InputDecoration(
                                        hintText:
                                            'Add 1-2 lines description...',
                                        hintStyle: TextStyle(
                                          color: Color(0xFF7A869A),
                                        ),
                                        isDense: true,
                                      ),
                                      onChanged: (val) =>
                                          _selectedTaskDetails[task]!['desc'] =
                                              val,
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: () async {
                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate: DateTime.now(),
                                              firstDate: DateTime.now(),
                                              lastDate: DateTime(2100),
                                              builder: (context, child) => Theme(
                                                data: ThemeData.light().copyWith(
                                                  colorScheme:
                                                      const ColorScheme.light(
                                                        primary: Color(
                                                          0xFF0052CC,
                                                        ),
                                                      ),
                                                ),
                                                child: child!,
                                              ),
                                            );
                                            if (picked != null) {
                                              setState(
                                                () =>
                                                    _selectedTaskDetails[task]!['date'] =
                                                        picked,
                                              );
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.calendar_today,
                                            size: 16,
                                          ),
                                          label: Text(
                                            _selectedTaskDetails[task]!['date'] ==
                                                    null
                                                ? 'Set Deadline'
                                                : '${_selectedTaskDetails[task]!['date'].day}/${_selectedTaskDetails[task]!['date'].month}/${_selectedTaskDetails[task]!['date'].year}',
                                          ),
                                        ),

                                        // Mark as Important Toggle Action
                                        InkWell(
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            setState(() {
                                              _selectedTaskDetails[task]!['important'] =
                                                  !(_selectedTaskDetails[task]!['important'] ==
                                                      true);
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  _selectedTaskDetails[task]!['important'] ==
                                                      true
                                                  ? Colors.amber.withValues(
                                                      alpha: 0.5,
                                                    )
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _selectedTaskDetails[task]!['important'] ==
                                                          true
                                                      ? Icons.star
                                                      : Icons.star_border,
                                                  color:
                                                      _selectedTaskDetails[task]!['important'] ==
                                                          true
                                                      ? Colors.amber
                                                      : const Color(0xFF7A869A),
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Priority',
                                                  style: TextStyle(
                                                    color:
                                                        _selectedTaskDetails[task]!['important'] ==
                                                            true
                                                        ? Colors.amber.shade700
                                                        : const Color(
                                                            0xFF7A869A,
                                                          ),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: _selectedTaskDetails.isEmpty || _isSubmitting
              ? null
              : () async {
                  setState(() => _isSubmitting = true);

                  final batch = FirebaseFirestore.instance.batch();
                  final now = DateTime.now();
                  final todayStr =
                      '${_getMonthName(now.month)} ${_getDaySuffix(now.day)}';

                  for (final entry in _selectedTaskDetails.entries) {
                    final taskName = entry.key;
                    final details = entry.value;
                    String? dateStr;
                    List<String> history = [];

                    if (details['date'] != null) {
                      dateStr =
                          '${details['date'].year}-${details['date'].month.toString().padLeft(2, '0')}-${details['date'].day.toString().padLeft(2, '0')}';
                      history.add(
                        'Changed by ${widget.currentUserName} to $dateStr on $todayStr',
                      );
                    }

                    final newDocRef = FirebaseFirestore.instance
                        .collection('tasks')
                        .doc();
                    batch.set(newDocRef, {
                      'title': taskName,
                      'project_id': widget.projectId,
                      'admin_id': widget.adminId,
                      'employee_id': widget.employeeId,
                      'description': details['desc'],
                      'deadline_date': dateStr,
                      'deadline_history': history,
                      'is_important':
                          details['important'] ==
                          true, // Saving Priority Status
                      'is_done': false,
                      'created_at': FieldValue.serverTimestamp(),
                    });
                  }
                  await batch.commit();

                  if (context.mounted) Navigator.pop(context);
                },
          child: _isSubmitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('ADD SELECTED'),
        ),
      ],
    );
  }
}
