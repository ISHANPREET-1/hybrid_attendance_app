import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import 'student_dashboard_screen.dart';

// ── NEW: Import the global session file ──
import '../../utils/user_session.dart';

// ─── Data ────────────────────────────────────────────────────────────────────

const _departments = [
  'Computer Science',
  'Information Technology',
  'Electronics & Communication',
  'Mechanical Engineering',
  'Civil Engineering',
  'Electrical Engineering',
  'Chemical Engineering',
];

const _semesters = ['1', '2', '3', '4', '5', '6', '7', '8'];
const _sections = ['A', 'B', 'C', 'D', 'E'];

// ─── Screen ──────────────────────────────────────────────────────────────────

class StudentSignupScreen extends StatefulWidget {
  const StudentSignupScreen({super.key});

  @override
  State<StudentSignupScreen> createState() => _StudentSignupScreenState();
}

class _StudentSignupScreenState extends State<StudentSignupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameFocus = FocusNode();
  final _rollFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _mobileFocus = FocusNode();

  final _nameCtrl = TextEditingController();
  final _rollCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();

  String? _department;
  String? _semester;
  String? _section;
  bool _isLoading = false;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    if (UserSession.studentRollNo != '000000') {
      _nameCtrl.text = UserSession.studentName;
      _rollCtrl.text = UserSession.studentRollNo;
      _emailCtrl.text = UserSession.studentEmail;
      _mobileCtrl.text = UserSession.studentMobile;
      if (_departments.contains(UserSession.studentDepartment)) {
        _department = UserSession.studentDepartment;
      }
      if (_semesters.contains(UserSession.studentSemester)) {
        _semester = UserSession.studentSemester;
      }
      if (_sections.contains(UserSession.studentSection)) {
        _section = UserSession.studentSection;
      }
    }
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic));
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    for (final n in [_nameFocus, _rollFocus, _emailFocus, _mobileFocus]) {
      n.dispose();
    }
    for (final c in [_nameCtrl, _rollCtrl, _emailCtrl, _mobileCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Validation helpers ────────────────────────────────────────────────────

  String? _required(String? v, String field) =>
      (v == null || v.trim().isEmpty) ? '$field is required' : null;

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    final re = RegExp(r'^[\w.-]+@[\w.-]+\.[a-zA-Z]{2,}$');
    return re.hasMatch(v.trim()) ? null : 'Enter a valid email address';
  }

  String? _validateMobile(String? v) {
    if (v == null || v.trim().isEmpty) return 'Mobile number is required';
    return v.trim().length == 10 ? null : 'Enter a valid 10-digit number';
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    // ── NEW: Save data to Global Session ──
    UserSession.studentName = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()
        : 'Student';
    UserSession.studentRollNo = _rollCtrl.text.trim().isNotEmpty
        ? _rollCtrl.text.trim()
        : '000000';
    UserSession.studentEmail = _emailCtrl.text.trim();
    UserSession.studentMobile = _mobileCtrl.text.trim();
    UserSession.studentDepartment = _department!;
    UserSession.studentSemester = _semester!;
    UserSession.studentSection = _section!;

    try {
      await UserSession.save();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save profile. Please retry.')),
      );
      return;
    }
    if (!mounted) return;
    // UPDATED NAVIGATION LOGIC:
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const StudentDashboardScreen()),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: _buildAppBar(isDark),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Form(
            key: _formKey,
            child: ListView(
              // 1. IMPROVEMENT: Dismiss keyboard on scroll
              physics: const BouncingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              // 2. IMPROVEMENT: Dynamically add padding when keyboard appears
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.of(context).viewInsets.bottom + 40,
              ),
              children: [
                // ── Header card ──────────────────────────────────────────
                _HeaderCard(isDark: isDark),
                const SizedBox(height: 20),

                // ── Form card (Centered and Constrained for responsiveness) ──
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: _FormCard(
                      isDark: isDark,
                      children: [
                        // Full Name
                        const _FieldLabel('Full Name'),
                        _AppField(
                          controller: _nameCtrl,
                          focusNode: _nameFocus,
                          hintText: 'Enter your full name',
                          prefixIcon: Icons.person_outline_rounded,
                          isDark: isDark,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              FocusScope.of(context).requestFocus(_rollFocus),
                          validator: (v) => _required(v, 'Full Name'),
                        ),
                        _Gap(),

                        // Roll Number
                        const _FieldLabel('Roll Number'),
                        _AppField(
                          controller: _rollCtrl,
                          focusNode: _rollFocus,
                          hintText: 'e.g. 21CS101',
                          prefixIcon: Icons.badge_outlined,
                          isDark: isDark,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              FocusScope.of(context).requestFocus(_emailFocus),
                          validator: (v) => _required(v, 'Roll Number'),
                        ),
                        _Gap(),

                        // Email
                        const _FieldLabel('Email'),
                        _AppField(
                          controller: _emailCtrl,
                          focusNode: _emailFocus,
                          hintText: 'you@college.edu',
                          prefixIcon: Icons.mail_outline_rounded,
                          isDark: isDark,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              FocusScope.of(context).requestFocus(_mobileFocus),
                          validator: _validateEmail,
                        ),
                        _Gap(),

                        // Mobile
                        const _FieldLabel('Mobile'),
                        _AppField(
                          controller: _mobileCtrl,
                          focusNode: _mobileFocus,
                          hintText: '10-digit number',
                          prefixIcon: Icons.phone_outlined,
                          isDark: isDark,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              FocusScope.of(context).unfocus(),
                          validator: _validateMobile,
                        ),
                        _Gap(),

                        // Department dropdown
                        const _FieldLabel('Department'),
                        _AppDropdown<String>(
                          value: _department,
                          hint: 'Select Department',
                          prefixIcon: Icons.account_balance_outlined,
                          items: _departments,
                          isDark: isDark,
                          onChanged: (v) => setState(() => _department = v),
                          validator: (v) =>
                              v == null ? 'Please select a department' : null,
                        ),
                        _Gap(),

                        // Semester + Section (side by side)
                        Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: _AppDropdown<String>(
                                value: _semester,
                                hint: 'Semester',
                                prefixIcon: Icons.calendar_today_outlined,
                                items: _semesters,
                                isDark: false,
                                onChanged: (v) => setState(() => _semester = v),
                                validator: (v) => v == null ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 1,
                              child: _AppDropdown<String>(
                                value: _section,
                                hint: 'Section',
                                prefixIcon: Icons.group_outlined,
                                items: _sections,
                                isDark: false,
                                onChanged: (v) => setState(() => _section = v),
                                validator: (v) => v == null ? 'Required' : null,
                              ),
                            ),
                          ],
                        ),
                        _Gap(),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Register button
                _RegisterButton(isLoading: _isLoading, onPressed: _submit),

                const SizedBox(height: 16),

                // Footer note
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.link_rounded,
                      size: 14,
                      color: context.appTextSecondary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Local profile only; device linking unavailable.',
                        style: AppTextStyles.bodySmall(
                          context.appTextSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar(bool isDark) => AppBar(
    backgroundColor: context.appBackground,
    elevation: 0,
    scrolledUnderElevation: 0,
    leading: IconButton(
      icon: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: context.appCard,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: AppColors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 16,
          color: context.appTextPrimary,
        ),
      ),
      onPressed: () => Navigator.pop(context),
    ),
    title: Text(
      'Student Profile',
      style: AppTextStyles.headlineSmall(context.appTextPrimary),
    ),
    centerTitle: true,
  );
}

// ─── Header Card ─────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final bool isDark;
  const _HeaderCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card(isDark: isDark),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(
              Icons.school_rounded,
              color: AppColors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Student Profile',
                  style: AppTextStyles.headlineSmall(context.appTextPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  'Fill in your details to get started',
                  style: AppTextStyles.bodySmall(context.appTextSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Form Card wrapper ────────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  const _FormCard({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

// ─── Field Label ──────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: AppTextStyles.labelMedium(
          context.appTextPrimary,
        ).copyWith(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}

// ─── Gap helper ───────────────────────────────────────────────────────────────

class _Gap extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox(height: 18);
}

// ─── Styled TextFormField ─────────────────────────────────────────────────────

class _AppField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final IconData prefixIcon;
  final bool isDark;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;
  final List<TextInputFormatter>? inputFormatters;

  const _AppField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.prefixIcon,
    required this.isDark,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.validator,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      style: AppTextStyles.bodyMedium(context.appTextPrimary),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: AppTextStyles.bodyMedium(
          context.appTextSecondary,
        ).copyWith(fontSize: 13),
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(
            prefixIcon,
            size: 18,
            color: focusNode.hasFocus
                ? AppColors.primary
                : context.appTextSecondary,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
        filled: true,
        fillColor: isDark ? AppColors.inputFillDark : AppColors.inputFillLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        errorStyle: const TextStyle(fontSize: 11, color: AppColors.error),
      ),
    );
  }
}

// ─── Styled DropdownFormField ─────────────────────────────────────────────────

class _AppDropdown<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final IconData prefixIcon;
  final List<T> items;
  final bool isDark;
  final ValueChanged<T?> onChanged;
  final FormFieldValidator<T>? validator;

  const _AppDropdown({
    required this.value,
    required this.hint,
    required this.prefixIcon,
    required this.items,
    required this.isDark,
    required this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final fillColor = isDark
        ? AppColors.inputFillDark
        : AppColors.inputFillLight;
    final borderColor = isDark ? AppColors.dividerDark : AppColors.dividerLight;

    return DropdownButtonFormField<T>(
      initialValue: value,
      validator: validator,
      onChanged: onChanged,
      isExpanded: true,
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        color: context.appTextSecondary,
        size: 20,
      ),
      dropdownColor: isDark ? AppColors.cardDark : AppColors.cardLight,
      style: AppTextStyles.bodyMedium(context.appTextPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.bodyMedium(
          context.appTextSecondary,
        ).copyWith(fontSize: 13),
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(prefixIcon, size: 18, color: context.appTextSecondary),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
        filled: true,
        fillColor: fillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        errorStyle: const TextStyle(fontSize: 11, color: AppColors.error),
      ),
      items: items
          .map(
            (e) => DropdownMenuItem<T>(
              value: e,
              child: Text(
                e.toString(),
                style: AppTextStyles.bodyMedium(context.appTextPrimary),
              ),
            ),
          )
          .toList(),
    );
  }
}

// ─── Register Button ──────────────────────────────────────────────────────────

class _RegisterButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;
  const _RegisterButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 54,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primaryLight],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.transparent,
          shadowColor: AppColors.transparent,
          foregroundColor: AppColors.white,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: AppColors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Continue',
                    style: AppTextStyles.labelLarge(AppColors.white),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
      ),
    );
  }
}
