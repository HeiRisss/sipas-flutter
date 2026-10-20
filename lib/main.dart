import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_headers.dart';
import 'data_siswa_screen.dart';
import 'registrasi_rfid_screen.dart';
import 'absensi_harian_screen.dart';
import 'laporan_screen.dart';
import 'kelas_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen.dart';

void main() {
  runApp(const SIPASApp());
}

const Color navy = Color(0xFF17365D);
const Color blue = Color(0xFF2563EB);
const Color background = Color(0xFFF4F7FB);

class SIPASApp extends StatelessWidget {
  const SIPASApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SIPAS - SMPN 1 Gambut',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Arial',
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(seedColor: blue),
      ),
      home: const AuthGate(),
    );
  }
}


class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('sipas_token');

    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() => _checking = false);
      }
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse('http://127.0.0.1:8000/api/user'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _isAuthenticated = true;
            _checking = false;
          });
        }
        return;
      }

      if (response.statusCode == 401) {
        await _clearSession(prefs);
      }

      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _checking = false;
        });
      }
    } catch (_) {
      // Jika server tidak dapat dijangkau, jangan buka dashboard.
      // Token tetap disimpan agar dapat diperiksa kembali.
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _checking = false;
        });
      }
    }
  }

  Future<void> _clearSession(
    SharedPreferences prefs,
  ) async {
    await prefs.remove('sipas_token');
    await prefs.remove('sipas_user_id');
    await prefs.remove('sipas_user_name');
    await prefs.remove('sipas_user_email');
    await prefs.remove('sipas_user_role');
  }

  Future<void> _logout() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('sipas_token');

  if (token != null && token.trim().isNotEmpty) {
    try {
      final response = await http
          .post(
            Uri.parse('http://127.0.0.1:8000/api/logout'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer ${token.trim()}',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint(
          'Logout API gagal: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Gagal menghubungi API logout: $e');
    }
  }

  await _clearSession(prefs);

  if (!mounted) return;

  setState(() {
    _isAuthenticated = false;
  });
}

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_isAuthenticated) {
      return SIPASHome(
        onLogout: _logout,
      );
    }
    return LoginScreen(
      onLoginSuccess: () {
        if (mounted) {
          setState(() {
            _isAuthenticated = true;
          });
        }
      },
    );
  }
}


// =====================================================
// HALAMAN UTAMA DAN NAVIGASI
// =====================================================
class SIPASHome extends StatefulWidget {
  final Future<void> Function() onLogout;

  const SIPASHome({
    super.key,
    required this.onLogout,
  });

  @override
  State<SIPASHome> createState() => _SIPASHomeState();
}

class _SIPASHomeState extends State<SIPASHome> {
  String halamanAktif = 'Dashboard';
  final List<Map<String, dynamic>> menuList = [
    {'title': 'Dashboard', 'icon': Icons.dashboard_outlined},
    {'title': 'Data Kelas', 'icon': Icons.class_outlined},
    {'title': 'Data Siswa', 'icon': Icons.people_outline},
    {'title': 'Registrasi RFID', 'icon': Icons.credit_card_outlined},
    {'title': 'Absensi Harian', 'icon': Icons.fact_check_outlined},
    {'title': 'Laporan', 'icon': Icons.bar_chart_outlined},
  ];
  Widget tampilkanHalaman() {
    switch (halamanAktif) {
      case 'Dashboard':
        return const DashboardScreen();
      case 'Data Kelas':
        return const KelasScreen();
      case 'Data Siswa':
        return const DataSiswaScreen();
      case 'Registrasi RFID':
        return const RegistrasiRFIDScreen();
      case 'Absensi Harian':
        return const AbsensiHarianScreen();
      case 'Laporan':
        return const LaporanScreen();
      default:
        return HalamanPlaceholder(judul: halamanAktif);
    }
  }

  Future<void> _konfirmasiLogout() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Konfirmasi Keluar'),
          content: const Text(
            'Apakah kamu yakin ingin keluar dari SIPAS?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Keluar'),
            ),
          ],
        );
      },
    );

    if (konfirmasi == true && mounted) {
      await widget.onLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: 230,
              child: Container(
                color: navy,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 24, 16, 24),
                      child: Row(
                        children: [
                          Icon(
                            Icons.school_outlined,
                            color: Colors.white,
                            size: 34,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SIPAS',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'SMPN 1 Gambut',
                                  style: TextStyle(
                                    color: Color(0xFFD6E4F5),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0xFF385779), height: 1),
                    const SizedBox(height: 14),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: menuList.map((menu) {
                          final String judul = menu['title'] as String;
                          final IconData ikon = menu['icon'] as IconData;
                          final bool terpilih = halamanAktif == judul;
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            child: Material(
                              color: terpilih
                                  ? const Color(0xFF2C4F77)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                dense: true,
                                selected: terpilih,
                                selectedTileColor: Colors.transparent,
                                leading: Icon(
                                  ikon,
                                  color: Colors.white,
                                  size: 21,
                                ),
                                title: Text(
                                  judul,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                                onTap: () {
                                  if (halamanAktif != judul) {
                                    setState(() => halamanAktif = judul);
                                  }
                                },
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),                    
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.logout,
                            color: Colors.white,
                            size: 21,
                          ),
                          title: const Text(
                            'Keluar',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                          onTap: _konfirmasiLogout,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'Prototype SIPAS v1.0',
                        style: TextStyle(
                          color: Color(0xFFD6E4F5),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: tampilkanHalaman()),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// DASHBOARD — DATA DARI LARAVEL, DAPAT DIFILTER PER KELAS
// =====================================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const String baseUrl = 'http://127.0.0.1:8000/api';
  static const String semuaKelasLabel = 'Semua Kelas';
  bool isLoading = true;
  String? errorMessage;
  List<String> daftarKelas = [];
  List<Map<String, dynamic>> semuaSiswa = [];
  List<Map<String, dynamic>> semuaAbsensi = [];
  String kelasTerpilih = semuaKelasLabel;
  
  @override
  void initState() {
    super.initState();
    muatDashboard();
  }

  String _tanggalUntukApi(DateTime tanggal) {
    final tahun = tanggal.year.toString().padLeft(4, '0');
    final bulan = tanggal.month.toString().padLeft(2, '0');
    final hari = tanggal.day.toString().padLeft(2, '0');
    return '$tahun-$bulan-$hari';
  }

  String _pesanError(http.Response response, String pesanDefault) {
    try {
      final dynamic hasil = jsonDecode(response.body);
      if (hasil is Map && hasil['message'] != null) {
        return hasil['message'].toString();
      }
      if (hasil is Map && hasil['errors'] is Map) {
        final errors = hasil['errors'] as Map;
        if (errors.isNotEmpty) {
          final pesan = errors.values.first;
          if (pesan is List && pesan.isNotEmpty) {
            return pesan.first.toString();
          }
        }
      }
    } catch (_) {
      // Respons bukan JSON; gunakan pesan default.
    }
    return '$pesanDefault (HTTP ${response.statusCode})';
  }

  bool _isAktif(Map<String, dynamic> data) {
    final dynamic nilai = data['aktif'];
    return nilai == true || nilai == 1 || nilai?.toString() == '1';
  }

  List<Map<String, dynamic>> _mapList(dynamic raw, String namaData) {
    if (raw is! List) {
      throw Exception('Format $namaData dari server tidak sesuai.');
    }
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> muatDashboard() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final tanggalApi = _tanggalUntukApi(DateTime.now());
      final responses = await Future.wait<http.Response>([

        http.get(
          Uri.parse('$baseUrl/kelas?aktif=1'),
          headers: await buildApiHeaders(),
        ),
        http.get(
          Uri.parse('$baseUrl/siswa'),
          headers: await buildApiHeaders(),
        ),
        http.get(
          Uri.parse('$baseUrl/absensi-siswa')
              .replace(queryParameters: {'tanggal': tanggalApi}),
          headers: await buildApiHeaders(),
        ),
      ]);
      final kelasResponse = responses[0];
      final siswaResponse = responses[1];
      final absensiResponse = responses[2];
      if (kelasResponse.statusCode != 200) {
        throw Exception(
          _pesanError(kelasResponse, 'Gagal mengambil daftar kelas'),
        );
      }
      if (siswaResponse.statusCode != 200) {
        throw Exception(
          _pesanError(siswaResponse, 'Gagal mengambil data siswa'),
        );
      }
      if (absensiResponse.statusCode != 200) {
        throw Exception(
          _pesanError(absensiResponse, 'Gagal mengambil data absensi'),
        );
      }
      final kelasJson = _mapList(jsonDecode(kelasResponse.body), 'kelas');
      final siswaJson = _mapList(jsonDecode(siswaResponse.body), 'siswa');
      final absensiJson = _mapList(jsonDecode(absensiResponse.body), 'absensi');
      final kelasBaru =
          kelasJson
              .where(_isAktif)
              .map((item) => (item['nama_kelas'] ?? '').toString().trim())
              .where((nama) => nama.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final siswaBaru = siswaJson.where(_isAktif).where((siswa) {
        final namaKelas = (siswa['kelas'] ?? '').toString();
        return namaKelas.isNotEmpty && kelasBaru.contains(namaKelas);
      }).toList();
      final absensiBaru = absensiJson.where((absensi) {
        final dynamic nested = absensi['siswa'];
        if (nested is! Map) return false;
        final siswa = Map<String, dynamic>.from(nested);
        return _isAktif(siswa) && (siswa['kelas'] ?? '').toString().isNotEmpty;
      }).toList();
      final pilihanMasihAda =
          kelasTerpilih == semuaKelasLabel || kelasBaru.contains(kelasTerpilih);
      final pilihanBaru = pilihanMasihAda ? kelasTerpilih : semuaKelasLabel;
      if (!mounted) return;
      setState(() {
        daftarKelas = kelasBaru;
        semuaSiswa = siswaBaru;
        semuaAbsensi = absensiBaru;
        kelasTerpilih = pilihanBaru;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> get siswaKelasTerpilih {
    if (kelasTerpilih == semuaKelasLabel) return semuaSiswa;
    return semuaSiswa
        .where((siswa) => (siswa['kelas'] ?? '').toString() == kelasTerpilih)
        .toList();
  }

  List<Map<String, dynamic>> get absensiKelasTerpilih {
    final idSiswa = siswaKelasTerpilih
        .map((siswa) => int.tryParse((siswa['id'] ?? '').toString()))
        .whereType<int>()
        .toSet();
    final unikPerSiswa = <int, Map<String, dynamic>>{};
    for (final absensi in semuaAbsensi) {
      final siswaId = int.tryParse((absensi['siswa_id'] ?? '').toString());
      if (siswaId != null && idSiswa.contains(siswaId)) {
        unikPerSiswa[siswaId] = absensi;
      }
    }
    final hasil = unikPerSiswa.values.toList();
    hasil.sort((a, b) => _waktuDariJson(b).compareTo(_waktuDariJson(a)));
    return hasil;
  }

  String _statusDariJson(Map<String, dynamic> absensi) {
    return (absensi['status'] ?? '').toString().toUpperCase();
  }

  String _waktuDariJson(Map<String, dynamic> absensi) {
    final waktu = (absensi['jam_masuk'] ?? '').toString();
    return waktu.isEmpty ? '--:--' : waktu;
  }

  int get totalSiswa => siswaKelasTerpilih.length;
  int get jumlahHadir => absensiKelasTerpilih
      .where((absensi) => _statusDariJson(absensi) == 'HADIR')
      .length;
  int get jumlahTerlambat => absensiKelasTerpilih
      .where((absensi) => _statusDariJson(absensi) == 'TERLAMBAT')
      .length;
  int get jumlahSakit => absensiKelasTerpilih
      .where((absensi) => _statusDariJson(absensi) == 'SAKIT')
      .length;

  int get jumlahIzin => absensiKelasTerpilih
      .where((absensi) => _statusDariJson(absensi) == 'IZIN')
      .length;

  int get jumlahAlpa => absensiKelasTerpilih
      .where((absensi) => _statusDariJson(absensi) == 'ALPA')
      .length;

  int get jumlahBelumAbsen {
    // Status SAKIT, IZIN, dan ALPA juga merupakan catatan absensi.
    final belum = totalSiswa - absensiKelasTerpilih.length;
    return belum < 0 ? 0 : belum;
  }

  List<Map<String, dynamic>> get aktivitasTerbaru =>
      absensiKelasTerpilih.take(5).toList();
  String _namaAktivitas(Map<String, dynamic> absensi) {
    final dynamic rawSiswa = absensi['siswa'];
    if (rawSiswa is Map) {
      final siswa = Map<String, dynamic>.from(rawSiswa);
      return (siswa['nama'] ?? 'Siswa').toString();
    }
    return 'Siswa';
  }

  String _kelasAktivitas(Map<String, dynamic> absensi) {
    final dynamic rawSiswa = absensi['siswa'];
    if (rawSiswa is Map) {
      final siswa = Map<String, dynamic>.from(rawSiswa);
      return (siswa['kelas'] ?? '-').toString();
    }
    return '-';
  }

  String _statusTampil(Map<String, dynamic> absensi) {
    switch (_statusDariJson(absensi)) {
      case 'HADIR':
        return 'Hadir';
      case 'TERLAMBAT':
        return 'Terlambat';
      case 'SAKIT':
        return 'Sakit';
      case 'IZIN':
        return 'Izin';
      case 'ALPA':
        return 'Alpa';
      default:
        return (absensi['status'] ?? 'Tercatat').toString();
    }
  }

  Color _warnaStatus(Map<String, dynamic> absensi) {
    switch (_statusDariJson(absensi)) {
      case 'TERLAMBAT':
        return const Color(0xFFE59A16);
      case 'SAKIT':
        return const Color(0xFF7C3AED);
      case 'IZIN':
        return const Color(0xFF2563EB);
      case 'ALPA':
        return const Color(0xFFDC4545);
      case 'HADIR':
      default:
        return const Color(0xFF15945B);
    }
  }

  void _tampilkanError() {
    if (errorMessage == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(errorMessage!),
          backgroundColor: Colors.red.shade700,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final String judulRingkasan = kelasTerpilih == semuaKelasLabel
        ? 'Ringkasan Semua Kelas'
        : 'Ringkasan Kelas $kelasTerpilih';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dashboard',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: navy,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sistem Informasi Presensi Siswa',
            style: TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE7F0FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  errorMessage == null
                      ? Icons.info_outline
                      : Icons.error_outline,
                  color: errorMessage == null ? blue : Colors.red,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    errorMessage == null
                        ? 'DATA DARI DATABASE — Ringkasan dan aktivitas dimuat dari Laravel.'
                        : 'Gagal memuat data dari Laravel: $errorMessage',
                    style: const TextStyle(color: navy),
                  ),
                ),
                IconButton(
                  tooltip: 'Muat ulang Dashboard',
                  onPressed: isLoading
                      ? null
                      : () async {
                          await muatDashboard();
                          if (mounted) _tampilkanError();
                        },
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, color: blue),
                ),
              ],
            ),
          ),
          if (isLoading && semuaSiswa.isEmpty) ...[
            const SizedBox(height: 24),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final filterKelas = SizedBox(
                width: constraints.maxWidth < 520 ? double.infinity : 230,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    'dashboard-kelas-$kelasTerpilih-${daftarKelas.length}',
                  ),
                  initialValue: kelasTerpilih,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Pilih Kelas',
                    prefixIcon: const Icon(Icons.school_outlined),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: semuaKelasLabel,
                      child: Text(semuaKelasLabel),
                    ),
                    ...daftarKelas.map(
                      (kelas) => DropdownMenuItem<String>(
                        value: kelas,
                        child: Text(kelas),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => kelasTerpilih = value);
                  },
                ),
              );
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      judulRingkasan,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    filterKelas,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      judulRingkasan,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  filterKelas,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final int columns = constraints.maxWidth >= 850 ? 4 : 2;
              final double cardWidth =
                  (constraints.maxWidth - (columns - 1) * 16) / columns;
              final String nilaiTotal = isLoading && semuaSiswa.isEmpty
                  ? '—'
                  : '$totalSiswa';
              final String nilaiHadir = isLoading && semuaSiswa.isEmpty
                  ? '—'
                  : '$jumlahHadir';
              final String nilaiTerlambat = isLoading && semuaSiswa.isEmpty
                  ? '—'
                  : '$jumlahTerlambat';
              final String nilaiSakit = isLoading && semuaSiswa.isEmpty
                  ? '—'
                  : '$jumlahSakit';
              final String nilaiIzin = isLoading && semuaSiswa.isEmpty
                  ? '—'
                  : '$jumlahIzin';
              final String nilaiAlpa = isLoading && semuaSiswa.isEmpty
                  ? '—'
                  : '$jumlahAlpa';
              final String nilaiBelumAbsen = isLoading && semuaSiswa.isEmpty
                  ? '—'
                  : '$jumlahBelumAbsen';

              final cards = <Widget>[
                StatCard(
                  title: 'Total Siswa',
                  value: nilaiTotal,
                  icon: Icons.groups_outlined,
                  color: blue,
                ),
                StatCard(
                  title: 'Hadir',
                  value: nilaiHadir,
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF15945B),
                ),
                StatCard(
                  title: 'Terlambat',
                  value: nilaiTerlambat,
                  icon: Icons.schedule,
                  color: const Color(0xFFE59A16),
                ),
                StatCard(
                  title: 'Sakit',
                  value: nilaiSakit,
                  icon: Icons.health_and_safety_outlined,
                  color: const Color(0xFF7C3AED),
                ),
                StatCard(
                  title: 'Izin',
                  value: nilaiIzin,
                  icon: Icons.event_available_outlined,
                  color: const Color(0xFF2563EB),
                ),
                StatCard(
                  title: 'Alpa',
                  value: nilaiAlpa,
                  icon: Icons.person_off_outlined,
                  color: const Color(0xFFDC4545),
                ),
                StatCard(
                  title: 'Belum Absen',
                  value: nilaiBelumAbsen,
                  icon: Icons.pending_actions_outlined,
                  color: const Color(0xFF64748B),
                ),
              ];

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: cards
                    .map((card) => SizedBox(width: cardWidth, child: card))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 30),
          const Text(
            'Aktivitas Absensi Terbaru',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFE5EAF1)),
            ),
            child: isLoading && aktivitasTerbaru.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : errorMessage != null && aktivitasTerbaru.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'Aktivitas belum dapat dimuat.\n$errorMessage',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.blueGrey),
                      ),
                    ),
                  )
                : aktivitasTerbaru.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'Belum ada aktivitas absensi untuk pilihan kelas ini hari ini.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.blueGrey),
                      ),
                    ),
                  )
                : Column(
                    children: List.generate(aktivitasTerbaru.length, (index) {
                      final absensi = aktivitasTerbaru[index];
                      return Column(
                        children: [
                          if (index > 0) const Divider(height: 1),
                          ActivityRow(
                            name: _namaAktivitas(absensi),
                            kelas: _kelasAktivitas(absensi),
                            time: _waktuDariJson(absensi),
                            status: _statusTampil(absensi),
                            color: _warnaStatus(absensi),
                          ),
                        ],
                      );
                    }),
                  ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// KARTU STATISTIK
// =====================================================
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5EAF1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 18),
          Text(
            value,
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.bold,
              color: navy,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// AKTIVITAS ABSENSI
// =====================================================
class ActivityRow extends StatelessWidget {
  final String name;
  final String kelas;
  final String time;
  final String status;
  final Color color;
  const ActivityRow({
    super.key,
    required this.name,
    required this.kelas,
    required this.time,
    required this.status,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFE7F0FF),
            child: Icon(Icons.person_outline, color: blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(
                  'Kelas $kelas',
                  style: const TextStyle(color: Colors.blueGrey, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(time, style: const TextStyle(color: Colors.blueGrey)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// PLACEHOLDER MENU YANG BELUM DIKERJAKAN
// =====================================================
class HalamanPlaceholder extends StatelessWidget {
  final String judul;
  const HalamanPlaceholder({super.key, required this.judul});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction_outlined, size: 56, color: blue),
            const SizedBox(height: 16),
            Text(
              judul,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: navy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Halaman ini akan dikembangkan pada tahap berikutnya.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey),
            ),
          ],
        ),
      ),
    );
  }
}
