import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'teacher_dashboard_screen.dart';

// ── NEW: Import the global session file ──
import '../../utils/user_session.dart';

class TeacherDetailsScreen extends StatefulWidget {
  const TeacherDetailsScreen({super.key});

  @override
  State<TeacherDetailsScreen> createState() => _TeacherDetailsScreenState();
}

class _TeacherDetailsScreenState extends State<TeacherDetailsScreen> {
  final _nameController = TextEditingController();
  final _facultyIdController = TextEditingController();
  final _classController = TextEditingController();

  String _selectedPosition = 'Assistant Professor';
  String _selectedDept = 'Computer Science';

  final List<String> _positions = [
    'Professor',
    'Associate Professor',
    'Assistant Professor',
  ];

  final List<String> _departments = [
    'Computer Science',
    'Information Technology',
    'Electronics',
    'Mechanical',
    'Civil',
  ];

  @override
  void initState() {
    super.initState();
    if (UserSession.teacherId != 'FAC-0000') {
      _nameController.text = UserSession.teacherName;
      _facultyIdController.text = UserSession.teacherId;
      if (_departments.contains(UserSession.teacherDept)) {
        _selectedDept = UserSession.teacherDept;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _facultyIdController.dispose();
    _classController.dispose();
    super.dispose();
  }

  Future<void> _submitDetails() async {
    if (_nameController.text.trim().isEmpty ||
        _facultyIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your name and faculty ID.')),
      );
      return;
    }
    // ── NEW: Save to Global Session ──
    // We check if the field is empty. If they forgot to type a name, it defaults to 'Teacher'.
    UserSession.teacherName = _nameController.text.isNotEmpty
        ? _nameController.text
        : 'Teacher';
    UserSession.teacherId = _facultyIdController.text.isNotEmpty
        ? _facultyIdController.text
        : 'FAC-0000';
    UserSession.teacherDept = _selectedDept;

    try {
      await UserSession.save();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save profile. Please retry.')),
      );
      return;
    }
    if (!mounted) return;
    // Navigate to Teacher Dashboard
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const TeacherDashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary,
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Faculty Setup',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please enter your professional details to set up your teaching dashboard.',
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),

              // ── Name Field ──
              _buildLabel('Full Name'),
              _buildTextField(
                controller: _nameController,
                hint: 'e.g., Dr. Alan Turing',
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 20),

              // ── Faculty ID & Class Row ──
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Faculty ID'),
                        _buildTextField(
                          controller: _facultyIdController,
                          hint: 'e.g., FAC-1042',
                          icon: Icons.badge_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Assigned Class'),
                        _buildTextField(
                          controller: _classController,
                          hint: 'e.g., CS-3A',
                          icon: Icons.class_outlined,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Department Dropdown ──
              _buildLabel('Department'),
              _buildDropdown(
                value: _selectedDept,
                items: _departments,
                icon: Icons.domain_rounded,
                onChanged: (val) => setState(() => _selectedDept = val!),
              ),
              const SizedBox(height: 20),

              // ── Position Dropdown ──
              _buildLabel('Position'),
              _buildDropdown(
                value: _selectedPosition,
                items: _positions,
                icon: Icons.work_outline_rounded,
                onChanged: (val) => setState(() => _selectedPosition = val!),
              ),
              const SizedBox(height: 40),

              // ── Submit Button ──
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _submitDetails,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Continue to Dashboard',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Helper Widgets for clean UI ───

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textDisabledLight),
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
        filled: true,
        fillColor: AppColors.cardSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.dividerLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.dividerLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required IconData icon,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.dividerLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textSecondary,
          ),
          dropdownColor: AppColors.cardSurface,
          style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
          items: items.map((String item) {
            return DropdownMenuItem(
              value: item,
              child: Row(
                children: [
                  Icon(icon, color: AppColors.textSecondary, size: 20),
                  const SizedBox(width: 12),
                  Text(item),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
