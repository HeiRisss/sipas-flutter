import 'dart:convert';
import 'dart:js_interop';
import 'api_headers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

const Color laporanNavy = Color(0xFF17365D);
const Color laporanBlue = Color(0xFF2563EB);
const Color laporanGreen = Color(0xFF15945B);
const Color laporanOrange = Color(0xFFE59A16);
const Color laporanRed = Color(0xFFDC4545);

class LaporanSiswa {
  final int siswaId;
  final String nis;
  final String nama;
  final String kelas;
  final String waktu;
  final String status;
  final String keterangan;
  const LaporanSiswa({
    required this.siswaId,
    required this.nis,
    required this.nama,
    required this.kelas,
    required this.waktu,
    required this.status,
    this.keterangan = '',
  });
}

class LaporanScreen extends StatefulWidget {
  const LaporanScreen({super.key});
  @override
  State<LaporanScreen> createState() => _LaporanScreenState();
}

class _LaporanScreenState extends State<LaporanScreen> {
  static const String baseUrl = 'http://127.0.0.1:8000/api';
  static const String semuaKelasLabel = 'Semua Kelas';
  final TextEditingController searchController = TextEditingController();
  DateTime tanggalDipilih = DateTime.now();
  String filterStatus = 'Semua';
  String filterKelas = 'VII A';
  List<String> daftarKelas = [];
  List<LaporanSiswa> semuaLaporan = [];
  bool isLoading = true;
  String? errorMessage;
  @override
  void initState() {
    super.initState();
    muatLaporan();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
  
  String tanggalApi(DateTime tanggal) {
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
      // Gunakan pesan bawaan jika respons bukan JSON.
    }
    return '$pesanDefault (HTTP ${response.statusCode})';
  }

  bool _isAktif(dynamic value) {
    return value == true || value == 1 || value?.toString() == '1';
  }

  String _statusTampilan(dynamic status) {
    final nilai = status?.toString().trim().toUpperCase();
    switch (nilai) {
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
      case null:
      case '':
        return 'Belum Absen';
      default:
        return status.toString();
    }
  }

  /// Daftar laporan sudah memuat semua kelas untuk tanggal terpilih.
  /// Pilihan kelas diterapkan di sisi Flutter agar ringkasan, tabel,
  /// dan hasil cetak menggunakan subset data yang sama.
  List<LaporanSiswa> get daftarLaporan {
    if (filterKelas == semuaKelasLabel) return semuaLaporan;
    return semuaLaporan.where((siswa) => siswa.kelas == filterKelas).toList();
  }

  Future<void> muatLaporan() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final tanggal = tanggalApi(tanggalDipilih);
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
              .replace(queryParameters: {'tanggal': tanggal}),
          headers: await buildApiHeaders(),
        ),
      ]);
      final kelasResponse = responses[0];
      final siswaResponse = responses[1];
      final absensiResponse = responses[2];
      if (kelasResponse.statusCode != 200) {
        throw Exception(
          pesanError(kelasResponse, 'Gagal mengambil daftar kelas'),
        );
      }
      if (siswaResponse.statusCode != 200) {
        throw Exception(
          pesanError(siswaResponse, 'Gagal mengambil data siswa'),
        );
      }
      if (absensiResponse.statusCode != 200) {
        throw Exception(
          pesanError(absensiResponse, 'Gagal mengambil data absensi'),
        );
      }
      final dynamic rawKelas = jsonDecode(kelasResponse.body);
      final dynamic rawSiswa = jsonDecode(siswaResponse.body);
      final dynamic rawAbsensi = jsonDecode(absensiResponse.body);
      if (rawKelas is! List || rawSiswa is! List || rawAbsensi is! List) {
        throw Exception('Format data dari server tidak sesuai.');
      }
      final kelasAktif = <String>[];
      for (final item in rawKelas) {
        if (item is! Map) continue;
        final kelas = Map<String, dynamic>.from(item);
        final namaKelas = kelas['nama_kelas']?.toString().trim() ?? '';
        if (namaKelas.isNotEmpty && _isAktif(kelas['aktif'])) {
          kelasAktif.add(namaKelas);
        }
      }
      kelasAktif.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final Map<int, Map<String, dynamic>> absensiPerSiswa = {};
      for (final item in rawAbsensi) {
        if (item is! Map) continue;
        final absensi = Map<String, dynamic>.from(item);
        final idSiswa = int.tryParse(absensi['siswa_id']?.toString() ?? '');
        if (idSiswa != null) {
          absensiPerSiswa[idSiswa] = absensi;
        }
      }
      final dataBaru = <LaporanSiswa>[];
      for (final item in rawSiswa) {
        if (item is! Map) continue;
        final siswa = Map<String, dynamic>.from(item);
        if (!_isAktif(siswa['aktif'])) continue;
        final idSiswa = int.tryParse(siswa['id']?.toString() ?? '');
        if (idSiswa == null) continue;
        final namaKelas = siswa['kelas']?.toString() ?? '';
        // Siswa hanya dihitung bila kelasnya masih aktif di tabel kelas.
        if (!kelasAktif.contains(namaKelas)) continue;
        final absensi = absensiPerSiswa[idSiswa];
        final waktu = absensi?['jam_masuk']?.toString();
        dataBaru.add(
          LaporanSiswa(
            siswaId: idSiswa,
            nis: siswa['nis']?.toString() ?? '',
            nama: siswa['nama']?.toString() ?? '',
            kelas: namaKelas,
            waktu: waktu == null || waktu.isEmpty ? '-' : waktu,
            status: _statusTampilan(absensi?['status']),
            keterangan: absensi?['keterangan']?.toString() ?? '',
          ),
        );
      }
      dataBaru.sort((a, b) {
        final urutKelas = a.kelas.toLowerCase().compareTo(
          b.kelas.toLowerCase(),
        );
        if (urutKelas != 0) return urutKelas;
        return a.nama.toLowerCase().compareTo(b.nama.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        daftarKelas = kelasAktif;
        semuaLaporan = dataBaru;
        if (filterKelas != semuaKelasLabel &&
            !daftarKelas.contains(filterKelas)) {
          filterKelas = daftarKelas.contains('VII A')
              ? 'VII A'
              : semuaKelasLabel;
        }
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
      }
    }
  }

  int get jumlahHadir => daftarLaporan.where((s) => s.status == 'Hadir').length;
  int get jumlahTerlambat =>
      daftarLaporan.where((s) => s.status == 'Terlambat').length;
  int get jumlahSakit => daftarLaporan.where((s) => s.status == 'Sakit').length;

  int get jumlahIzin => daftarLaporan.where((s) => s.status == 'Izin').length;

  int get jumlahAlpa => daftarLaporan.where((s) => s.status == 'Alpa').length;

  int get jumlahBelumAbsen =>
      daftarLaporan.where((s) => s.status == 'Belum Absen').length;
  List<LaporanSiswa> get laporanTampil {
    final query = searchController.text.trim().toLowerCase();
    return daftarLaporan.where((siswa) {
      final cocokPencarian =
          siswa.nama.toLowerCase().contains(query) ||
          siswa.nis.toLowerCase().contains(query);
      final cocokStatus =
          filterStatus == 'Semua' || siswa.status == filterStatus;
      return cocokPencarian && cocokStatus;
    }).toList();
  }

  String formatTanggal(DateTime tanggal) {
    const bulan = [
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
    return '${tanggal.day} ${bulan[tanggal.month - 1]} ${tanggal.year}';
  }

  Color warnaStatus(String status) {
    switch (status) {
      case 'Hadir':
        return laporanGreen;
      case 'Terlambat':
        return laporanOrange;
      case 'Sakit':
        return const Color(0xFF7C3AED);
      case 'Izin':
        return laporanBlue;
      case 'Alpa':
        return laporanRed;
      default:
        return Colors.blueGrey;
    }
  }

  Future<void> pilihTanggal() async {
    final tanggal = await showDatePicker(
      context: context,
      initialDate: tanggalDipilih,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Pilih tanggal laporan',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (tanggal != null && mounted) {
      setState(() {
        tanggalDipilih = DateTime(tanggal.year, tanggal.month, tanggal.day);
      });
      await muatLaporan();
    }
  }

  String htmlEscape(String value) => const HtmlEscape().convert(value);
  void cetakLaporan() {
    final tanggal = formatTanggal(tanggalDipilih);
    final kelasTampil = filterKelas;
    final data = laporanTampil;
    final baris = data.asMap().entries.map((entry) {
      final nomor = entry.key + 1;
      final siswa = entry.value;
      return '''
        <tr>
          <td>$nomor</td>
          <td>${htmlEscape(siswa.nis)}</td>
          <td>${htmlEscape(siswa.nama)}</td>
          <td>${htmlEscape(siswa.kelas)}</td>
          <td>${htmlEscape(siswa.waktu)}</td>
          <td>${htmlEscape(siswa.status)}</td>
          <td>${htmlEscape(siswa.keterangan.isEmpty ? '-' : siswa.keterangan)}</td>
        </tr>
      ''';
    }).join();
    final htmlLaporan =
        '''
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Laporan Absensi SIPAS</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: Arial, sans-serif; color: #222; margin: 24px; font-size: 12px; }
  .kop { text-align: center; border-bottom: 2px solid #17365D; padding-bottom: 14px; }
  .kop h1 { color: #17365D; font-size: 20px; margin-bottom: 6px; }
  h2 { text-align: center; color: #17365D; font-size: 17px; margin-top: 22px; }
  .tanggal { text-align: center; }
  .ringkasan { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 8px; margin: 20px 0; }
  .kartu { border: 1px solid #ccc; padding: 10px 5px; text-align: center; }
  @media (max-width: 600px) { .ringkasan { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
  .angka { font-size: 20px; font-weight: bold; margin-bottom: 5px; }
  table { width: 100%; border-collapse: collapse; margin-top: 18px; }
  th, td { border: 1px solid #999; padding: 8px; text-align: left; }
  th { background: #e7f0ff; color: #17365D; }
  .catatan { margin-top: 18px; font-size: 10px; }
  @page { size: A4 portrait; margin: 12mm; }
  @media print { body { margin: 0; } thead { display: table-header-group; } tr { break-inside: avoid; } }
</style>
</head>
<body>
  <div class="kop">
    <h1>SMP NEGERI 1 GAMBUT</h1>
    <p>Sistem Informasi Presensi Siswa (SIPAS)</p>
  </div>
  <h2>LAPORAN ABSENSI SISWA</h2>
  <p class="tanggal">${htmlEscape(kelasTampil)} | Tanggal: ${htmlEscape(tanggal)}</p>
  <div class="ringkasan">
    <div class="kartu"><div class="angka">${daftarLaporan.length}</div>Total Siswa</div>
    <div class="kartu"><div class="angka">$jumlahHadir</div>Hadir</div>
    <div class="kartu"><div class="angka">$jumlahTerlambat</div>Terlambat</div>
    <div class="kartu"><div class="angka">$jumlahSakit</div>Sakit</div>
    <div class="kartu"><div class="angka">$jumlahIzin</div>Izin</div>
    <div class="kartu"><div class="angka">$jumlahAlpa</div>Alpa</div>
    <div class="kartu"><div class="angka">$jumlahBelumAbsen</div>Belum Absen</div>
  </div>
  <p>Menampilkan ${data.length} dari ${daftarLaporan.length} siswa${filterStatus == 'Semua' ? '' : ' dengan status ${htmlEscape(filterStatus)}'}.</p>
  <table>
    <thead><tr><th>No.</th><th>NIS</th><th>Nama Siswa</th><th>Kelas</th><th>Waktu</th><th>Status</th><th>Keterangan</th></tr></thead>
    <tbody>$baris</tbody>
  </table>
  <p class="catatan">Data diambil dari database SIPAS melalui Laravel API.</p>
  <script>window.addEventListener('load', () => { window.print(); });</script>
</body>
</html>
''';
    final blob = web.Blob(
      <web.BlobPart>[htmlLaporan.toJS].toJS,
      web.BlobPropertyBag(type: 'text/html;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    web.window.open(url, '_blank');
  }

  Widget kartuRingkasan({
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
              fontSize: 27,
              fontWeight: FontWeight.bold,
              color: laporanNavy,
            ),
          ),
          const SizedBox(height: 5),
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
        labelText: 'Status',
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
        if (value != null) setState(() => filterStatus = value);
      },
    );
  }

  Widget dropdownFilterKelas() {
    final pilihan = <String>[semuaKelasLabel, ...daftarKelas];
    final nilai = pilihan.contains(filterKelas) ? filterKelas : semuaKelasLabel;
    return DropdownButtonFormField<String>(
      initialValue: nilai,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Kelas Laporan',
        prefixIcon: const Icon(Icons.school_outlined),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: pilihan
          .map(
            (kelas) => DropdownMenuItem<String>(
              value: kelas,
              child: Text(kelas, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) setState(() => filterKelas = value);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = laporanTampil;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Laporan Absensi',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: laporanNavy,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Rekap kehadiran siswa berdasarkan kelas dan tanggal.',
            style: TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE7F0FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: laporanBlue),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'DATA DARI DATABASE — Laporan dimuat dari Laravel dan dapat difilter berdasarkan kelas.',
                    style: TextStyle(color: laporanNavy),
                  ),
                ),
                IconButton(
                  tooltip: 'Muat ulang laporan',
                  onPressed: isLoading ? null : muatLaporan,
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, color: laporanBlue),
                ),
              ],
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEEE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Gagal memuat laporan: $errorMessage',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5EAF1)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isiTanggal = OutlinedButton.icon(
                  onPressed: isLoading ? null : pilihTanggal,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(formatTanggal(tanggalDipilih)),
                );
                final tombolCetak = FilledButton.icon(
                  onPressed:
                      isLoading || errorMessage != null || daftarLaporan.isEmpty
                      ? null
                      : cetakLaporan,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Cetak / Simpan PDF'),
                );
                if (constraints.maxWidth < 600) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Tanggal Laporan',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      isiTanggal,
                      const SizedBox(height: 16),
                      dropdownFilterKelas(),
                      const SizedBox(height: 10),
                      tombolCetak,
                    ],
                  );
                }
                return Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      color: laporanBlue,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      'Tanggal Laporan',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 16),
                    isiTanggal,
                    const SizedBox(width: 16),
                    Expanded(child: dropdownFilterKelas()),
                    const SizedBox(width: 14),
                    tombolCetak,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Ringkasan Kehadiran',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (errorMessage == null)
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1100
                    ? 4
                    : constraints.maxWidth >= 700
                    ? 3
                    : 2;
                final cardWidth =
                    (constraints.maxWidth - (columns - 1) * 14) / columns;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: kartuRingkasan(
                        judul: 'Total Siswa',
                        jumlah: daftarLaporan.length,
                        ikon: Icons.groups_outlined,
                        warna: laporanBlue,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: kartuRingkasan(
                        judul: 'Hadir',
                        jumlah: jumlahHadir,
                        ikon: Icons.check_circle_outline,
                        warna: laporanGreen,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: kartuRingkasan(
                        judul: 'Terlambat',
                        jumlah: jumlahTerlambat,
                        ikon: Icons.schedule,
                        warna: laporanOrange,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: kartuRingkasan(
                        judul: 'Sakit',
                        jumlah: jumlahSakit,
                        ikon: Icons.health_and_safety_outlined,
                        warna: const Color(0xFF7C3AED),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: kartuRingkasan(
                        judul: 'Izin',
                        jumlah: jumlahIzin,
                        ikon: Icons.event_available_outlined,
                        warna: laporanBlue,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: kartuRingkasan(
                        judul: 'Alpa',
                        jumlah: jumlahAlpa,
                        ikon: Icons.person_off_outlined,
                        warna: laporanRed,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: kartuRingkasan(
                        judul: 'Belum Absen',
                        jumlah: jumlahBelumAbsen,
                        ikon: Icons.pending_actions_outlined,
                        warna: Colors.blueGrey,
                      ),
                    ),
                  ],
                );
              },
            ),
          const SizedBox(height: 28),
          const Text(
            'Rekap Siswa',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final pencarian = TextField(
                controller: searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Cari nama atau NIS...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
              if (constraints.maxWidth < 520) {
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
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Menampilkan ${isLoading || errorMessage != null ? 0 : data.length} dari '
            '${isLoading || errorMessage != null ? 0 : daftarLaporan.length} siswa',
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
            child: isLoading
                ? const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : errorMessage != null
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Laporan tidak dapat dimuat.'),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: muatLaporan,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Coba Lagi'),
                          ),
                        ],
                      ),
                    ),
                  )
                : data.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: Text('Data tidak ditemukan.')),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        const Color(0xFFF4F7FB),
                      ),
                      columns: const [
                        DataColumn(label: Text('No.')),
                        DataColumn(label: Text('NIS')),
                        DataColumn(label: Text('Nama Siswa')),
                        DataColumn(label: Text('Kelas')),
                        DataColumn(label: Text('Waktu')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Keterangan')),
                      ],
                      rows: List.generate(data.length, (index) {
                        final siswa = data[index];
                        final warna = warnaStatus(siswa.status);
                        return DataRow(
                          cells: [
                            DataCell(Text('${index + 1}')),
                            DataCell(Text(siswa.nis)),
                            DataCell(
                              SizedBox(width: 180, child: Text(siswa.nama)),
                            ),
                            DataCell(Text(siswa.kelas)),
                            DataCell(Text(siswa.waktu)),
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
                              SizedBox(
                                width: 220,
                                child: Text(
                                  siswa.keterangan.isEmpty
                                      ? '-'
                                      : siswa.keterangan,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Text(
            '$filterKelas • ${formatTanggal(tanggalDipilih)} • '
            'Total ${daftarLaporan.length} siswa',
            style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
