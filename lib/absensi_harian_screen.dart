import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_headers.dart';
const Color absensiNavy = Color(0xFF17365D);
const Color absensiBlue = Color(0xFF2563EB);
const Color absensiGreen = Color(0xFF15945B);
const Color absensiOrange = Color(0xFFE59A16);
const Color absensiRed = Color(0xFFDC4545);
class DataAbsensi {
  final int siswaId;
  final String nis;
  final String nama;
  final String kelas;
  final String? uid;
  final bool kartuAktif;
  final DateTime? waktu;
  final String status;
  final String? keterangan;
  const DataAbsensi({
    required this.siswaId,
    required this.nis,
    required this.nama,
    required this.kelas,
    required this.uid,
    required this.kartuAktif,
    this.waktu,
    this.status = 'Belum Absen',
    this.keterangan,
  });
}
class AbsensiHarianScreen extends StatefulWidget {
  const AbsensiHarianScreen({super.key});
  @override
  State<AbsensiHarianScreen> createState() => _AbsensiHarianScreenState();
}
class _AbsensiHarianScreenState extends State<AbsensiHarianScreen> {
  static const String baseUrl = 'http://127.0.0.1:8000/api';
  final TextEditingController searchController = TextEditingController();
  // Kolom ini menerima UID yang diketikkan RFID Reader USB (mode keyboard/HID).
  final TextEditingController rfidController = TextEditingController();
  final FocusNode rfidFocusNode = FocusNode();
  DateTime tanggalAbsensi = DateTime.now();
  List<DataAbsensi> daftarAbsensi = [];
  List<String> daftarKelas = [];
  String? kelasTerpilih;
  String kataKunci = '';
  String filterStatus = 'Semua';
  String? errorMessage;
  bool isLoading = true;
  bool isSubmitting = false;
  bool isScanningRfid = false;
  
  @override
  void initState() {
    super.initState();
    muatData();

    // Minta fokus saat halaman pertama kali muncul. Fokus akan diminta lagi
    // setelah muatData selesai karena proses pemuatan dapat membangun ulang UI.
    _fokuskanKolomRfid();
  }

  void _fokuskanKolomRfid() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || isScanningRfid || isSubmitting) return;
      if (rfidFocusNode.canRequestFocus) {
        rfidFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    rfidController.dispose();
    rfidFocusNode.dispose();
    super.dispose();
  }
  String tanggalUntukApi(DateTime tanggal) {
    final tahun = tanggal.year.toString().padLeft(4, '0');
    final bulan = tanggal.month.toString().padLeft(2, '0');
    final hari = tanggal.day.toString().padLeft(2, '0');
    return '$tahun-$bulan-$hari';
  }
  String pesanError(http.Response response, String pesanDefault) {
    try {
      final dynamic hasil = jsonDecode(response.body);
      if (hasil is Map) {
        final dynamic errors = hasil['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final dynamic pesan = errors.values.first;
          if (pesan is List && pesan.isNotEmpty) {
            return pesan.first.toString();
          }
        }
        if (hasil['message'] != null) {
          return hasil['message'].toString();
        }
      }
    } catch (_) {
      // Gunakan pesan default jika respons bukan JSON.
    }
    return '$pesanDefault (HTTP ${response.statusCode})';
  }
  bool nilaiBool(dynamic value) {
    return value == true || value == 1 || value?.toString() == '1';
  }
  DateTime? parseJamMasuk(dynamic value, DateTime tanggal) {
    if (value == null || value.toString().trim().isEmpty) return null;
    final bagian = value.toString().split(':');
    if (bagian.length < 2) return null;
    try {
      final jam = int.parse(bagian[0]);
      final menit = int.parse(bagian[1]);
      final detik = bagian.length >= 3
          ? int.parse(bagian[2].split('.').first)
          : 0;
      return DateTime(
        tanggal.year,
        tanggal.month,
        tanggal.day,
        jam,
        menit,
        detik,
      );
    } catch (_) {
      return null;
    }
  }
  String statusUntukTampilan(dynamic value) {
    switch (value?.toString().toUpperCase()) {
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
        return 'Belum Absen';
    }
  }
  Future<void> muatData() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      // Ambil daftar kelas aktif agar halaman tidak lagi terkunci ke VII A.
      final kelasResponse = await http.get(
        Uri.parse('$baseUrl/kelas?aktif=1'),
        headers: await buildApiHeaders(),
      );
      if (kelasResponse.statusCode != 200) {
        throw Exception(
          pesanError(kelasResponse, 'Gagal mengambil daftar kelas'),
        );
      }
      final dynamic rawKelas = jsonDecode(kelasResponse.body);
      if (rawKelas is! List) {
        throw Exception('Format daftar kelas dari server tidak sesuai.');
      }
      final kelasBaru = <String>[];
      for (final item in rawKelas) {
        if (item is! Map) continue;
        final kelas = Map<String, dynamic>.from(item);
        final namaKelas = kelas['nama_kelas']?.toString().trim() ?? '';
        if (namaKelas.isNotEmpty && !kelasBaru.contains(namaKelas)) {
          kelasBaru.add(namaKelas);
        }
      }
      kelasBaru.sort();
      if (kelasBaru.isEmpty) {
        throw Exception(
          'Belum ada kelas aktif. Tambahkan kelas di menu Data Kelas.',
        );
      }
      // Pertahankan pilihan pengguna; jika belum ada, utamakan VII A.
      final String kelasTarget =
          kelasTerpilih != null && kelasBaru.contains(kelasTerpilih)
          ? kelasTerpilih!
          : kelasBaru.contains('VII A')
          ? 'VII A'
          : kelasBaru.first;
      final tanggalApi = tanggalUntukApi(tanggalAbsensi);
      final responses = await Future.wait<http.Response>([
        http.get(
          Uri.parse('$baseUrl/siswa')
              .replace(queryParameters: {'kelas': kelasTarget}),
          headers: await buildApiHeaders(),
        ),
        http.get(
          Uri.parse('$baseUrl/absensi-siswa').replace(
            queryParameters: {'tanggal': tanggalApi, 'kelas': kelasTarget},
          ),
          headers: await buildApiHeaders(),
        ),
      ]);
      final siswaResponse = responses[0];
      final absensiResponse = responses[1];
      if (siswaResponse.statusCode != 200) {
        throw Exception(
          pesanError(siswaResponse, 'Gagal mengambil daftar siswa'),
        );
      }
      if (absensiResponse.statusCode != 200) {
        throw Exception(
          pesanError(absensiResponse, 'Gagal mengambil data absensi'),
        );
      }
      final dynamic rawSiswa = jsonDecode(siswaResponse.body);
      final dynamic rawAbsensi = jsonDecode(absensiResponse.body);
      if (rawSiswa is! List || rawAbsensi is! List) {
        throw Exception('Format data dari server tidak sesuai.');
      }
      final Map<int, Map<String, dynamic>> absensiBySiswa = {};
      for (final item in rawAbsensi) {
        if (item is! Map) continue;
        final record = Map<String, dynamic>.from(item);
        final idValue = record['siswa_id'];
        if (idValue == null) continue;
        final siswaId = int.tryParse(idValue.toString());
        if (siswaId != null) {
          absensiBySiswa[siswaId] = record;
        }
      }
      final List<DataAbsensi> hasil = [];
      for (final item in rawSiswa) {
        if (item is! Map) continue;
        final siswa = Map<String, dynamic>.from(item);
        if (siswa['kelas']?.toString() != kelasTarget) continue;
        if (!nilaiBool(siswa['aktif'])) continue;
        final id = int.tryParse(siswa['id'].toString());
        if (id == null) continue;
        final rawKartu = siswa['kartu_rfid'];
        final Map<String, dynamic>? kartu = rawKartu is Map
            ? Map<String, dynamic>.from(rawKartu)
            : null;
        final uidKartu = kartu?['uid']?.toString();
        final kartuAktif = kartu != null && nilaiBool(kartu['aktif']);
        final record = absensiBySiswa[id];
        final waktu = record == null
            ? null
            : parseJamMasuk(record['jam_masuk'], tanggalAbsensi);
        hasil.add(
          DataAbsensi(
            siswaId: id,
            nis: siswa['nis']?.toString() ?? '',
            nama: siswa['nama']?.toString() ?? '',
            kelas: siswa['kelas']?.toString() ?? kelasTarget,
            uid: uidKartu == null || uidKartu.isEmpty ? null : uidKartu,
            kartuAktif: kartuAktif,
            waktu: waktu,
            status: record == null
                ? 'Belum Absen'
                : statusUntukTampilan(record['status']),
            keterangan: record == null || record['keterangan'] == null
                ? null
                : record['keterangan'].toString(),
          ),
        );
      }
      hasil.sort(
        (a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        daftarKelas = kelasBaru;
        kelasTerpilih = kelasTarget;
        daftarAbsensi = hasil;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        // Setelah data selesai dimuat, siapkan kolom untuk kartu berikutnya.
        _fokuskanKolomRfid();
      }
    }
  }
  Future<void> pilihKelas(String? value) async {
    if (value == null || value == kelasTerpilih) return;
    setState(() {
      kelasTerpilih = value;
      filterStatus = 'Semua';
    });
    await muatData();
  }
  int get jumlahHadir =>
      daftarAbsensi.where((siswa) => siswa.status == 'Hadir').length;
  int get jumlahTerlambat =>
      daftarAbsensi.where((siswa) => siswa.status == 'Terlambat').length;
  int get jumlahSakit =>
      daftarAbsensi.where((siswa) => siswa.status == 'Sakit').length;
  int get jumlahIzin =>
      daftarAbsensi.where((siswa) => siswa.status == 'Izin').length;
  int get jumlahAlpa =>
      daftarAbsensi.where((siswa) => siswa.status == 'Alpa').length;
  int get jumlahBelumAbsen =>
      daftarAbsensi.where((siswa) => siswa.status == 'Belum Absen').length;
  List<DataAbsensi> get dataTampil {
    return daftarAbsensi.where((siswa) {
      final kata = kataKunci.toLowerCase().trim();
      final cocokPencarian =
          siswa.nama.toLowerCase().contains(kata) ||
          siswa.nis.toLowerCase().contains(kata);
      final cocokStatus =
          filterStatus == 'Semua' || siswa.status == filterStatus;
      return cocokPencarian && cocokStatus;
    }).toList();
  }
  String formatWaktu(DateTime? waktu) {
    if (waktu == null) return '-';
    return '${waktu.hour.toString().padLeft(2, '0')}:'
        '${waktu.minute.toString().padLeft(2, '0')}:'
        '${waktu.second.toString().padLeft(2, '0')}';
  }
  String formatTanggal(DateTime tanggal) {
    const namaBulan = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    return '${tanggal.day} ${namaBulan[tanggal.month - 1]} ${tanggal.year}';
  }
  Color warnaStatus(String status) {
    switch (status) {
      case 'Hadir':
        return absensiGreen;
      case 'Terlambat':
        return absensiOrange;
      case 'Sakit':
        return const Color(0xFF7C3AED);
      case 'Izin':
        return absensiBlue;
      case 'Alpa':
        return absensiRed;
      default:
        return const Color(0xFF64748B);
    }
  }
  void tampilkanPesan(String pesan, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(pesan),
          backgroundColor: error ? Colors.red.shade700 : null,
        ),
      );
  }
  Future<void> konfirmasiAbsensi(DataAbsensi siswa) async {
    if (siswa.status != 'Belum Absen') {
      tampilkanPesan('${siswa.nama} sudah tercatat absensinya.');
      return;
    }
    if (siswa.uid == null || !siswa.kartuAktif) {
      tampilkanPesan(
        'Siswa ini belum memiliki kartu RFID aktif. Daftarkan kartu terlebih dahulu.',
        error: true,
      );
      return;
    }
    final setuju = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Catat Absensi'),
        content: Text(
          'Catat kehadiran ${siswa.nama} menggunakan kartu RFID terdaftar?\n\n'
          'Kelas: ${siswa.kelas}\n'
          'UID: ${siswa.uid}\n'
          'Permintaan akan dikirim ke Laravel dan disimpan di database.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Catat Absensi'),
          ),
        ],
      ),
    );
    if (setuju == true && mounted) {
      await catatAbsensi(siswa);
    }
  }
  Future<void> catatAbsensi(DataAbsensi siswa) async {
    if (isSubmitting || isScanningRfid) return;
    final uid = siswa.uid;
    if (uid == null || !siswa.kartuAktif) {
      tampilkanPesan('Siswa belum memiliki kartu RFID aktif.', error: true);
      return;
    }
    setState(() {
      isSubmitting = true;
    });
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/absensi-siswa/scan'),
        headers: await buildApiHeaders(jsonBody: true),
        body: jsonEncode({'uid': uid}),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(pesanError(response, 'Gagal mencatat absensi'));
      }
      String pesan = 'Permintaan absensi berhasil diproses.';
      bool duplikat = false;
      try {
        final dynamic hasil = jsonDecode(response.body);
        if (hasil is Map) {
          if (hasil['message'] != null) {
            pesan = hasil['message'].toString();
          }
          duplikat = hasil['duplikat'] == true;
        }
      } catch (_) {
        // Respons HTTP berhasil; gunakan pesan default.
      }
      await muatData();
      if (!mounted) return;
      tampilkanPesan(pesan, error: duplikat);
    } catch (e) {
      tampilkanPesan(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }
  /// Dipanggil ketika RFID Reader USB mengetikkan UID lalu mengirim Enter.
  /// Reader yang tampil sebagai USB Keyboard/HID tidak memerlukan driver serial.
  Future<void> prosesScanRfid(String nilaiMasuk) async {
    final uid = nilaiMasuk
        .trim()
        .replaceAll(RegExp(r'[\s:-]'), '')
        .toUpperCase();
    // Kosongkan secepatnya agar pembacaan kartu berikutnya siap diterima.
    rfidController.clear();
    if (uid.isEmpty) return;
    if (isScanningRfid || isSubmitting) {
      tampilkanPesan(
        'SIPAS masih memproses permintaan sebelumnya. Coba lagi sebentar.',
      );
      return;
    }
    // Sesuai validasi UID pada AbsensiSiswaController Laravel.
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(uid) || uid.length.isOdd) {
      tampilkanPesan(
        'Format UID tidak valid: $uid. Pastikan reader mengirim UID kartu, bukan teks lain.',
        error: true,
      );
      _fokuskanKolomRfid();
      return;
    }
    setState(() => isScanningRfid = true);
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/absensi-siswa/scan'),
        headers: await buildApiHeaders(jsonBody: true),
        body: jsonEncode({'uid': uid}),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
          pesanError(response, 'Gagal mencatat absensi dari kartu RFID'),
        );
      }
      dynamic hasil;
      try {
        hasil = jsonDecode(response.body);
      } catch (_) {
        hasil = null;
      }
      var pesan = 'Permintaan absensi kartu RFID berhasil diproses.';
      if (hasil is Map && hasil['message'] != null) {
        pesan = hasil['message'].toString();
      }
      // Pindahkan pilihan kelas ke kelas pemilik kartu bila respons Laravel
      // menyertakan data siswa; ini membantu catatan baru langsung terlihat.
      if (hasil is Map && hasil['siswa'] is Map) {
        final siswa = Map<String, dynamic>.from(hasil['siswa'] as Map);
        final kelasSiswa = siswa['kelas']?.toString();
        if (kelasSiswa != null && daftarKelas.contains(kelasSiswa)) {
          kelasTerpilih = kelasSiswa;
        }
      }
      // Endpoint scan memakai tanggal saat ini dari Laravel. Tampilkan tanggal
      // hari ini di layar supaya hasil scan langsung bisa ditemukan.
      tanggalAbsensi = DateTime.now();
      filterStatus = 'Semua';
      kataKunci = '';
      searchController.clear();
      await muatData();
      if (!mounted) return;
      tampilkanPesan(pesan);
    } catch (e) {
      if (!mounted) return;
      tampilkanPesan(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) {
        setState(() => isScanningRfid = false);
        // TextField baru aktif kembali; siapkan untuk kartu berikutnya.
        _fokuskanKolomRfid();
      }
    }
  }
  /// Mencatat SAKIT, IZIN, atau ALPA melalui endpoint Laravel.
  /// Dialog memiliki controller sendiri agar tidak dilepas sebelum
  /// animasi penutupan dialog benar-benar selesai.
  Future<void> catatKetidakhadiran(DataAbsensi siswa) async {
    if (isSubmitting || isScanningRfid) return;
    if (siswa.status != 'Belum Absen') {
      tampilkanPesan(
        '${siswa.nama} sudah memiliki catatan absensi.',
        error: true,
      );
      return;
    }
    final formData = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _FormKetidakhadiranDialog(
        siswa: siswa,
        tanggal: formatTanggal(tanggalAbsensi),
      ),
    );
    if (formData == null || !mounted) return;
    setState(() => isSubmitting = true);
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/absensi-siswa/manual'),
        headers: await buildApiHeaders(jsonBody: true),
        body: jsonEncode({
          'siswa_id': siswa.siswaId,
          'tanggal': tanggalUntukApi(tanggalAbsensi),
          'status': formData['status'],
          'keterangan': formData['keterangan'],
        }),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
          pesanError(response, 'Gagal menyimpan status ketidakhadiran'),
        );
      }
      String pesan = 'Status ketidakhadiran berhasil disimpan.';
      try {
        final dynamic hasil = jsonDecode(response.body);
        if (hasil is Map && hasil['message'] != null) {
          pesan = hasil['message'].toString();
        }
      } catch (_) {
        // Gunakan pesan default jika respons kosong atau bukan JSON.
      }
      await muatData();
      if (!mounted) return;
      tampilkanPesan(pesan);
    } catch (e) {
      tampilkanPesan(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) {
        setState(() => isSubmitting = false);
      }
    }
  }
  Future<void> pilihTanggal() async {
    final tanggal = await showDatePicker(
      context: context,
      initialDate: tanggalAbsensi,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Pilih tanggal absensi',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (tanggal == null || !mounted) return;
    setState(() {
      tanggalAbsensi = tanggal;
    });
    await muatData();
  }
  Widget kartuStatistik({
    required String judul,
    required int jumlah,
    required IconData ikon,
    required Color warna,
  }) {
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
          Icon(ikon, color: warna, size: 27),
          const SizedBox(height: 14),
          Text(
            '$jumlah',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: absensiNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            judul,
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
  Widget dropdownFilterStatus() {
    return DropdownButtonFormField<String>(
      initialValue: filterStatus,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Filter Status',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: const [
        DropdownMenuItem(value: 'Semua', child: Text('Semua Status')),
        DropdownMenuItem(value: 'Hadir', child: Text('Hadir')),
        DropdownMenuItem(value: 'Terlambat', child: Text('Terlambat')),
        DropdownMenuItem(value: 'Sakit', child: Text('Sakit')),
        DropdownMenuItem(value: 'Izin', child: Text('Izin')),
        DropdownMenuItem(value: 'Alpa', child: Text('Alpa')),
        DropdownMenuItem(value: 'Belum Absen', child: Text('Belum Absen')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          filterStatus = value;
        });
      },
    );
  }
  Widget pencarianDanFilter({required bool vertikal}) {
    final pencarian = TextField(
      controller: searchController,
      onChanged: (value) {
        setState(() {
          kataKunci = value;
        });
      },
      decoration: InputDecoration(
        hintText: 'Cari nama atau NIS...',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    if (vertikal) {
      return Column(
        children: [
          pencarian,
          const SizedBox(height: 10),
          dropdownFilterStatus(),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: pencarian),
        const SizedBox(width: 12),
        SizedBox(width: 180, child: dropdownFilterStatus()),
      ],
    );
  }
  Widget dropdownKelas() {
    final pilihanValid =
        kelasTerpilih != null && daftarKelas.contains(kelasTerpilih)
        ? kelasTerpilih
        : null;
    return DropdownButtonFormField<String>(
      key: ValueKey<String?>(pilihanValid),
      initialValue: pilihanValid,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Pilih Kelas',
        prefixIcon: const Icon(Icons.school_outlined),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      hint: Text(isLoading ? 'Memuat kelas...' : 'Pilih kelas'),
      items: daftarKelas.map((kelas) {
        return DropdownMenuItem<String>(
          value: kelas,
          child: Text(kelas, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: isLoading || isSubmitting || isScanningRfid
          ? null
          : pilihKelas,
    );
  }
  Widget tabelAbsensi(List<DataAbsensi> data) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 42, color: absensiRed),
              const SizedBox(height: 12),
              const Text(
                'Gagal memuat data absensi dari Laravel.',
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: muatData,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }
    if (data.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(30),
        child: Center(
          child: Text(
            'Tidak ada siswa yang cocok dengan pencarian atau filter.',
            style: TextStyle(color: Colors.blueGrey),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 24,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F7FB)),
        columns: const [
          DataColumn(label: Text('No.')),
          DataColumn(label: Text('NIS')),
          DataColumn(label: Text('Nama Siswa')),
          DataColumn(label: Text('Kelas')),
          DataColumn(label: Text('Waktu')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Aksi')),
        ],
        rows: List.generate(data.length, (index) {
          final siswa = data[index];
          final warna = warnaStatus(siswa.status);
          return DataRow(
            cells: [
              DataCell(Text('${index + 1}')),
              DataCell(Text(siswa.nis)),
              DataCell(SizedBox(width: 170, child: Text(siswa.nama))),
              DataCell(Text(siswa.kelas)),
              DataCell(Text(formatWaktu(siswa.waktu))),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: warna.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    siswa.status,
                    style: TextStyle(
                      color: warna,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              DataCell(
                siswa.status == 'Belum Absen'
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: siswa.uid != null && siswa.kartuAktif
                                ? 'Uji catat absensi dengan UID terdaftar'
                                : 'Siswa belum memiliki kartu RFID aktif',
                            onPressed:
                                isSubmitting ||
                                    siswa.uid == null ||
                                    !siswa.kartuAktif
                                ? null
                                : () => konfirmasiAbsensi(siswa),
                            icon: const Icon(
                              Icons.how_to_reg_outlined,
                              color: absensiBlue,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Catat Sakit, Izin, atau Alpa',
                            onPressed: isSubmitting
                                ? null
                                : () => catatKetidakhadiran(siswa),
                            icon: const Icon(
                              Icons.note_add_outlined,
                              color: absensiOrange,
                            ),
                          ),
                        ],
                      )
                    : Icon(
                        Icons.check_circle,
                        color: warnaStatus(siswa.status),
                      ),
              ),
            ],
          );
        }),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final data = dataTampil;
    final kelasTeks = kelasTerpilih ?? 'Memuat kelas...';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Absensi Harian',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: absensiNavy,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pantau kehadiran siswa berdasarkan kelas.',
            style: TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 24),
          // INFORMASI DATABASE DAN TOMBOL MUAT ULANG
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE7F0FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: absensiBlue),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'DATA DARI DATABASE — Kehadiran dimuat dari Laravel. '
                    'Gunakan ikon biru untuk uji RFID atau ikon oranye untuk Sakit, Izin, dan Alpa.',
                    style: TextStyle(color: absensiNavy),
                  ),
                ),
                IconButton(
                  tooltip: 'Muat ulang data',
                  onPressed: isLoading || isScanningRfid || isSubmitting
                      ? null
                      : muatData,
                  icon: const Icon(Icons.refresh, color: absensiBlue),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // INPUT RFID USB (KEYBOARD/HID)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5EAF1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Absensi dengan RFID Reader USB',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Kolom UID akan otomatis disiapkan. Tempelkan kartu; reader USB akan mengetik UID dan biasanya mengirim Enter secara otomatis.',
                  style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: rfidController,
                  focusNode: rfidFocusNode,
                  autofocus: true,
                  enabled: !isScanningRfid && !isSubmitting,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  onSubmitted: prosesScanRfid,
                  decoration: InputDecoration(
                    labelText: 'UID Kartu RFID',
                    hintText: 'Tempelkan kartu RFID di reader',
                    prefixIcon: const Icon(Icons.nfc, color: absensiBlue),
                    suffixIcon: isScanningRfid
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Fokuskan kolom RFID',
                            onPressed: () => rfidFocusNode.requestFocus(),
                            icon: const Icon(Icons.center_focus_strong),
                          ),
                    filled: true,
                    fillColor: const Color(0xFFFAFCFF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      isScanningRfid ? Icons.sync : Icons.info_outline,
                      size: 16,
                      color: isScanningRfid ? absensiOrange : Colors.blueGrey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isScanningRfid ? 'Memproses UID ke Laravel...' : 'UID disimpan sebagai teks, termasuk angka nol di depan.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // TANGGAL DAN FILTER KELAS
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5EAF1)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final infoTanggal = Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      color: absensiBlue,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tanggal Absensi',
                            style: TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatTanggal(tanggalAbsensi),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Pilih tanggal',
                      onPressed: isScanningRfid || isSubmitting
                          ? null
                          : pilihTanggal,
                      icon: const Icon(Icons.edit_calendar_outlined),
                    ),
                  ],
                );
                final pemilihKelas = dropdownKelas();
                if (constraints.maxWidth < 600) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      infoTanggal,
                      const SizedBox(height: 14),
                      pemilihKelas,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: infoTanggal),
                    const SizedBox(width: 20),
                    SizedBox(width: 190, child: pemilihKelas),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          // RINGKASAN KEHADIRAN SESUAI KELAS YANG DIPILIH
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 850 ? 3 : 2;
              final cardWidth =
                  (constraints.maxWidth - (columns - 1) * 14) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: kartuStatistik(
                      judul: 'Hadir',
                      jumlah: jumlahHadir,
                      ikon: Icons.check_circle_outline,
                      warna: absensiGreen,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: kartuStatistik(
                      judul: 'Terlambat',
                      jumlah: jumlahTerlambat,
                      ikon: Icons.schedule,
                      warna: absensiOrange,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: kartuStatistik(
                      judul: 'Sakit',
                      jumlah: jumlahSakit,
                      ikon: Icons.health_and_safety_outlined,
                      warna: const Color(0xFF7C3AED),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: kartuStatistik(
                      judul: 'Izin',
                      jumlah: jumlahIzin,
                      ikon: Icons.event_available_outlined,
                      warna: absensiBlue,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: kartuStatistik(
                      judul: 'Alpa',
                      jumlah: jumlahAlpa,
                      ikon: Icons.person_off_outlined,
                      warna: absensiRed,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: kartuStatistik(
                      judul: 'Belum Absen',
                      jumlah: jumlahBelumAbsen,
                      ikon: Icons.pending_actions_outlined,
                      warna: const Color(0xFF64748B),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          Text(
            'Daftar Kehadiran Siswa — $kelasTeks',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              return pencarianDanFilter(vertikal: constraints.maxWidth < 520);
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Menampilkan ${isLoading || errorMessage != null ? 0 : data.length} dari '
            '${isLoading || errorMessage != null ? 0 : daftarAbsensi.length} siswa',
            style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Card(
            color: Colors.white,
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE5EAF1)),
            ),
            child: tabelAbsensi(data),
          ),
          const SizedBox(height: 12),
          const Text(
            'Absensi RFID dan status ketidakhadiran disimpan melalui Laravel. '
            'Batas keterlambatan sementara: pukul 07.15 WITA.',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
}
/// Dialog terpisah yang mengelola TextEditingController sepanjang hidupnya.
/// Ini menghindari dispose controller ketika route dialog baru mulai menutup.
class _FormKetidakhadiranDialog extends StatefulWidget {
  final DataAbsensi siswa;
  final String tanggal;
  const _FormKetidakhadiranDialog({required this.siswa, required this.tanggal});
  @override
  State<_FormKetidakhadiranDialog> createState() =>
      _FormKetidakhadiranDialogState();
}
class _FormKetidakhadiranDialogState extends State<_FormKetidakhadiranDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _keteranganController = TextEditingController();
  String _statusDipilih = 'SAKIT';
  @override
  void dispose() {
    _keteranganController.dispose();
    super.dispose();
  }
  void _simpan() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(<String, String>{
      'status': _statusDipilih,
      'keterangan': _keteranganController.text.trim(),
    });
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Catat Ketidakhadiran'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.siswa.nama} • ${widget.siswa.kelas}\n'
                  'NIS: ${widget.siswa.nis}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tanggal: ${widget.tanggal}',
                  style: const TextStyle(color: Colors.blueGrey),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: _statusDipilih,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Status Ketidakhadiran',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'SAKIT', child: Text('Sakit')),
                    DropdownMenuItem(value: 'IZIN', child: Text('Izin')),
                    DropdownMenuItem(
                      value: 'ALPA',
                      child: Text('Alpa (sudah diverifikasi)'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _statusDipilih = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _keteranganController,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan',
                    hintText: 'Contoh: demam atau izin keperluan keluarga',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Keterangan wajib diisi.';
                    }
                    if (value.trim().length > 500) {
                      return 'Keterangan maksimal 500 karakter.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 4),
                const Text(
                  'Catatan akan disimpan ke database untuk tanggal absensi yang dipilih.',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _simpan,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Simpan Status'),
        ),
      ],
    );
  }
}