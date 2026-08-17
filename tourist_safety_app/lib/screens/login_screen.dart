import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'guide_dashboard.dart';
import 'tourist_login_screen.dart';
import 'tourist_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isLogin = true;
  bool isLoading = false;
  String selectedRole = "tourist";
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final TextEditingController nationalityController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ================= FORGOT PASSWORD =================
  Future<void> _forgotPassword() async {
    final TextEditingController resetEmailController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Forgot Password?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter your email address to receive a password reset link:"),
            const SizedBox(height: 15),
            TextField(
              controller: resetEmailController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.email),
                labelText: "Email",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final email = resetEmailController.text.trim();
              final messenger = ScaffoldMessenger.of(context);
              final nav = Navigator.of(context);
              if (email.isEmpty) {
                messenger.showSnackBar(
                  const SnackBar(content: Text("Please enter your email")),
                );
                return;
              }
              try {
                await _auth.sendPasswordResetEmail(email: email);
                if (!mounted) return;
                nav.pop();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text("Password reset email sent!"),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text("Error: ${e.toString()}")),
                );
              }
            },
            child: const Text("Send", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ================= ROLE SELECTION (POST-SIGNUP) =================
  void _showRoleSelectionDialog(String uid) {
    showDialog(
      context: context,
      barrierDismissible: false, // Force them to choose
      builder: (context) {
        String? tempRole; // Null initially to force explicit selection
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("Select Your Role", style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Please select your role to continue:"),
                  const SizedBox(height: 20),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: tempRole == "tourist" ? Colors.indigo : Colors.grey.shade300),
                    ),
                    leading: const Icon(Icons.person, color: Colors.indigo),
                    title: const Text("Tourist", style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text("I am a traveler looking for safety services"),
                    trailing: tempRole == "tourist" ? const Icon(Icons.check_circle, color: Colors.indigo) : null,
                    onTap: () => setState(() => tempRole = "tourist"),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: tempRole == "guide" ? Colors.teal : Colors.grey.shade300),
                    ),
                    leading: const Icon(Icons.tour, color: Colors.teal),
                    title: const Text("Tour Guide", style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text("I am a guide managing tourist groups"),
                    trailing: tempRole == "guide" ? const Icon(Icons.check_circle, color: Colors.teal) : null,
                    onTap: () => setState(() => tempRole = "guide"),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tempRole != null ? Colors.indigo : Colors.grey,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: tempRole == null
                      ? null
                      : () async {
                          final selected = tempRole!;
                          Navigator.pop(context); // Close role selection
                          
                          // Save role to Firestore
                          await _firestore.collection('users').doc(uid).update({
                            'role': selected,
                          });

                          if (selected == "tourist") {
                            // Trigger Step 2 for Tourist
                            _showLocationSourceDialog(uid);
                          } else {
                            // Guide directly routed
                            _routeUserByRole("guide");
                          }
                        },
                  child: const Text("Continue", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ================= LOCATION SOURCE SELECTION (TOURIST ONLY) =================
  void _showLocationSourceDialog(String uid) {
    showDialog(
      context: context,
      barrierDismissible: false, // Force them to choose
      builder: (context) {
        String? tempSource; // Null initially to force explicit selection
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("Location Source", style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Where does the location data come from?"),
                  const SizedBox(height: 20),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: tempSource == "gps" ? Colors.indigo : Colors.grey.shade300),
                    ),
                    leading: const Icon(Icons.phone_android, color: Colors.indigo),
                    title: const Text("Phone GPS", style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text("The phone uses its GPS to track your location"),
                    trailing: tempSource == "gps" ? const Icon(Icons.check_circle, color: Colors.indigo) : null,
                    onTap: () => setState(() => tempSource = "gps"),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: tempSource == "esp8266" ? Colors.orange : Colors.grey.shade300),
                    ),
                    leading: const Icon(Icons.watch, color: Colors.orange),
                    title: const Text("ESP8266 Device", style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text("A wearable GPS device is used to track your location"),
                    trailing: tempSource == "esp8266" ? const Icon(Icons.check_circle, color: Colors.orange) : null,
                    onTap: () => setState(() => tempSource = "esp8266"),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tempSource != null ? Colors.indigo : Colors.grey,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: tempSource == null
                      ? null
                      : () async {
                          final selectedSource = tempSource!;
                          Navigator.pop(context); // Close dialog

                          // Save gpsSource to Firestore
                          await _firestore.collection('users').doc(uid).update({
                            'gpsSource': selectedSource,
                          });

                          // Route to tourist dashboard
                          _routeUserByRole("tourist");
                        },
                  child: const Text("Finish", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ================= ROUTING BY ROLE =================
  void _routeUserByRole(String role) {
    if (role == 'guide') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const GuideDashboard(),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const TouristDashboard(),
        ),
      );
    }
  }

  // ================= REGISTER =================
  Future<void> registerUser() async {
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();
    final nationality = nationalityController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty || confirmPassword.isEmpty || nationality.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill in all fields"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Passwords do not match"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    try {
      setState(() => isLoading = true);

      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // We set the role to empty on signup to trigger role selection dialog on first login!
      await _firestore
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        'name': name,
        'email': email,
        'nationality': nationality,
        'role': '',
        'gpsSource': '',
        'groupCode': '',
        'createdAt': DateTime.now(),
      });

      if (!mounted) return;

      setState(() {
        isLoading = false;
        isLogin = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Registration Successful! Please login."),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? "Registration Failed"),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("An unexpected error occurred: ${e.toString()}"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ================= LOGIN =================
  Future<void> loginUser() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter both email and password"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    try {
      setState(() => isLoading = true);

      UserCredential userCredential =
          await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      try {
        DocumentSnapshot userDoc = await _firestore
            .collection('users')
            .doc(userCredential.user!.uid)
            .get();

        if (!mounted) return;
        setState(() => isLoading = false);

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>?;
        String role = (data != null && data.containsKey('role')) ? data['role'] : '';
        String gpsSource = (data != null && data.containsKey('gpsSource')) ? data['gpsSource'] : '';
        String groupCode = (data != null && data.containsKey('groupCode')) ? data['groupCode'] : '';

        if (role.isEmpty) {
          _showRoleSelectionDialog(userCredential.user!.uid);
        } else if (role == 'tourist' && gpsSource.isEmpty) {
          _showLocationSourceDialog(userCredential.user!.uid);
        } else if (role == 'tourist' && groupCode.isEmpty) {
          // Tourist has no group code yet, navigate to code entry screen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const TouristLoginScreen()),
          );
        } else {
          _routeUserByRole(role);
        }
      } else {
        // Document does not exist — prompt for role
        _showRoleSelectionDialog(userCredential.user!.uid);
      }
      } catch (e) {
        if (!mounted) return;
        setState(() => isLoading = false);

        // Fallback to tourist dashboard if there is a Firestore issue so the user is not blocked
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Database warning: ${e.toString()}. Logged in as Tourist."),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const TouristDashboard(),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? "Login Failed"),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("An unexpected error occurred: ${e.toString()}"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF4F46E5),
              Color(0xFF06B6D4),
              Color(0xFF22C55E),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: Column(
              children: [
                const SizedBox(height: 70),

                const Icon(
                  Icons.travel_explore,
                  size: 90,
                  color: Colors.white,
                ),

                const SizedBox(height: 25),

                Text(
                  isLogin ? "Welcome Back 👋" : "Create Account ✨",
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  isLogin ? "Login to continue" : "Register as a tourist",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 40),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Column(
                    children: [
                      if (!isLogin)
                        TextField(
                          controller: nameController,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.person),
                            labelText: "Full Name",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),

                      if (!isLogin) const SizedBox(height: 20),

                      TextField(
                        controller: emailController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.email),
                          labelText: "Email",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      TextField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword ? Icons.visibility_off : Icons.visibility,
                            ),
                            onPressed: () => setState(() => obscurePassword = !obscurePassword),
                          ),
                          labelText: "Password",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),

                      if (isLogin)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _forgotPassword,
                            child: const Text(
                              "Forgot Password?",
                              style: TextStyle(color: Colors.indigo),
                            ),
                          ),
                        ),

                      if (!isLogin) ...[
                        const SizedBox(height: 20),

                        TextField(
                          controller: confirmPasswordController,
                          obscureText: obscureConfirmPassword,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock_reset),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                              ),
                              onPressed: () => setState(() => obscureConfirmPassword = !obscureConfirmPassword),
                            ),
                            labelText: "Confirm Password",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        TextField(
                          controller: nationalityController,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.flag),
                            labelText: "Nationality",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),

                      ],

                      const SizedBox(height: 25),

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          onPressed: isLoading
                              ? null
                              : () {
                                  if (isLogin) {
                                    loginUser();
                                  } else {
                                    registerUser();
                                  }
                                },
                          child: isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Text(
                                  isLogin ? "LOGIN" : "REGISTER",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 15),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isLogin
                                ? "Don't have an account?"
                                : "Already have an account?",
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                isLogin = !isLogin;
                              });
                            },
                            child: Text(
                              isLogin ? "Register" : "Login",
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}