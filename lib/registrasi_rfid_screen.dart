import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'api_headers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SiswaRfid {
  final int id;
  final String nis;
  final String nama;
  final String kelas;
  final bool aktif;

  const _SiswaRfid({
    required this.id,
    required this.nis,
    required this.nama,
    required this.kelas,
    required this.aktif,
  });

  factory _SiswaRfid.fromJson(Map<String, dynamic> json) {
    final statusAktif = json['aktif'];

    return _SiswaRfid(
      id: int.parse(json['id'].toString()),
      nis: json['nis']?.toString() ?? '',
      nama: json['nama']?.toString() ?? '',
      kelas: json['kelas']?.toString() ?? '-',
      aktif: statusAktif == true ||
          statusAktif == 1 ||
          statusAktif?.toString() == '1' ||
          statusAktif?.toString().toLowerCase() == 'true',
    );
  }
}

class _KartuRfid {
  final int id;
  final int siswaId;
  final String nis;
  final String nama;
  final String kelas;
  final String uid;
  final bool aktif;

  const _KartuRfid({
    required this.id,
    required this.siswaId,
    required this.nis,
    required this.nama,
    required this.kelas,
    required this.uid,
    required this.aktif,
  });

  factory _KartuRfid.fromJson(Map<String, dynamic> json) {
    final rawSiswa = json['siswa'];
    final Map<String, dynamic> siswa = rawSiswa is Map
        ? Map<String, dynamic>.from(rawSiswa)
        : <String, dynamic>{};

    final statusAktif = json['aktif'];

    return _KartuRfid(
      id: int.parse(json['id'].toString()),
      siswaId: int.parse(json['siswa_id'].toString()),
      nis: siswa['nis']?.toString() ?? '-',
      nama: siswa['nama']?.toString() ?? 'Siswa tidak ditemukan',
      kelas: siswa['kelas']?.toString() ?? '-',
      uid: json['uid']?.toString() ?? '',
      aktif: statusAktif == true ||
          statusAktif == 1 ||
          statusAktif?.toString() == '1' ||
          statusAktif?.toString().toLowerCase() == 'true',
    );
  }
}

class RegistrasiRFIDScreen extends StatefulWidget {
  const RegistrasiRFIDScreen({super.key});

  @override
  State<RegistrasiRFIDScreen> createState() =>
      _RegistrasiRFIDScreenState();
}

class _RegistrasiRFIDScreenState extends State<RegistrasiRFIDScreen> {
  static const String baseUrl = 'http://127.0.0.1:8000/api';

  final TextEditingController uidController = TextEditingController();

  int? siswaTerpilih;
  List<_SiswaRfid> daftarSiswa = [];
  List<_KartuRfid> kartuTerdaftar = [];
  List<String> daftarKelas = [];
  String filterKelas = 'Semua Kelas';

  bool isLoading = true;
  bool isSaving = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    muatData();
    muatRolePengguna();
  }

  @override
  void dispose() {
    uidController.dispose();
    super.dispose();
  }

    bool isAdmin = false;

    Future<void> muatRolePengguna() async {
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('sipas_user_role') ?? '';

      if (!mounted) return;

      setState(() {
        isAdmin = role.toLowerCase() == 'admin';
      });
    }
  // Siswa aktif yang belum mempunyai kartu terdaftar.
  List<_SiswaRfid> get siswaBelumTerdaftar {
    return daftarSiswa.where((siswa) {
      final sudahTerdaftar = kartuTerdaftar.any(
        (kartu) => kartu.siswaId == siswa.id,
      );
      return siswa.aktif && !sudahTerdaftar;
    }).toList();
  }

  List<_SiswaRfid> get siswaTersediaUntukKelas {
    return siswaBelumTerdaftar.where((siswa) {
      return filterKelas == 'Semua Kelas' || siswa.kelas == filterKelas;
    }).toList();
  }

  List<_KartuRfid> get kartuTampil {
    return kartuTerdaftar.where((kartu) {
      return filterKelas == 'Semua Kelas' || kartu.kelas == filterKelas;
    }).toList();
  }

  bool nilaiAktif(dynamic value) {
    final String teks = value?.toString().toLowerCase() ?? '';
    return value == true || value == 1 || teks == '1' || teks == 'true';
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

  Future<void> muatData() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
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
          Uri.parse('$baseUrl/kartu-rfid'),
          headers: await buildApiHeaders(),
        ),
      ]);

      final kelasResponse = responses[0];
      final siswaResponse = responses[1];
      final kartuResponse = responses[2];

      if (kelasResponse.statusCode != 200) {
        throw Exception(
          pesanError(kelasResponse, 'Gagal mengambil daftar kelas'),
        );
      }

      if (siswaResponse.statusCode != 200) {
        throw Exception(
          pesanError(siswaResponse, 'Gagal mengambil daftar siswa'),
        );
      }

      if (kartuResponse.statusCode != 200) {
        throw Exception(
          pesanError(kartuResponse, 'Gagal mengambil daftar kartu RFID'),
        );
      }

      final dynamic rawKelas = jsonDecode(kelasResponse.body);
      final dynamic rawSiswa = jsonDecode(siswaResponse.body);
      final dynamic rawKartu = jsonDecode(kartuResponse.body);

      if (rawKelas is! List || rawSiswa is! List || rawKartu is! List) {
        throw Exception('Format data dari server tidak sesuai.');
      }

      final kelasSet = <String>{};
      for (final item in rawKelas) {
        if (item is! Map) continue;
        final kelas = Map<String, dynamic>.from(item);
        if (!nilaiAktif(kelas['aktif'])) continue;
        final namaKelas = (kelas['nama_kelas'] ?? '').toString().trim();
        if (namaKelas.isNotEmpty) kelasSet.add(namaKelas);
      }
      final kelasBaru = kelasSet.toList()..sort();

      final siswaBaru = rawSiswa.map<_SiswaRfid>((item) {
        return _SiswaRfid.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
      }).toList();

      final kartuBaru = rawKartu.map<_KartuRfid>((item) {
        return _KartuRfid.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
      }).toList();

      if (!mounted) return;

      setState(() {
        daftarKelas = kelasBaru;
        if (filterKelas != 'Semua Kelas' &&
            !kelasBaru.contains(filterKelas)) {
          filterKelas = 'Semua Kelas';
        }

        daftarSiswa = siswaBaru;
        kartuTerdaftar = kartuBaru;

        if (siswaTerpilih != null &&
            !siswaBaru.any(
              (siswa) =>
                  siswa.id == siswaTerpilih &&
                  siswa.aktif &&
                  (filterKelas == 'Semua Kelas' ||
                      siswa.kelas == filterKelas) &&
                  !kartuBaru.any((kartu) => kartu.siswaId == siswa.id),
            )) {
          siswaTerpilih = null;
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

  String normalisasiUid(String value) {
    return value.replaceAll(RegExp(r'[\s:-]'), '').toUpperCase();
  }

  Future<void> simpanRegistrasi() async {
    if (isLoading || isSaving) return;

    if (errorMessage != null) {
      tampilkanPesan(
        'Hubungkan aplikasi ke server terlebih dahulu.',
        error: true,
      );
      return;
    }

    final idSiswa = siswaTerpilih;
    if (idSiswa == null) {
      tampilkanPesan('Pilih siswa terlebih dahulu.', error: true);
      return;
    }

    final uid = normalisasiUid(uidController.text);
    if (uid.isEmpty) {
      tampilkanPesan('UID kartu RFID wajib diisi.', error: true);
      return;
    }

    if (!RegExp(r'^[0-9A-F]+$').hasMatch(uid) || uid.length.isOdd) {
      tampilkanPesan(
        'UID harus berupa pasangan karakter heksadesimal, '
        'contoh: A1B2C3D4.',
        error: true,
      );
      return;
    }

    final siswaCocok = siswaTersediaUntukKelas
        .where((item) => item.id == idSiswa)
        .toList();

    if (siswaCocok.isEmpty) {
      tampilkanPesan(
        'Siswa tidak ditemukan atau sudah memiliki kartu.',
        error: true,
      );
      await muatData();
      return;
    }

    // Simpan nama sebelum await agar tidak perlu mencari ulang setelah reload.
    final namaSiswa = siswaCocok.first.nama;

    setState(() {
      isSaving = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/kartu-rfid'),
        headers: await buildApiHeaders(jsonBody: true),
        body: jsonEncode({
          'siswa_id': idSiswa,
          'uid': uid,
        }),
      );

      if (response.statusCode != 201) {
        throw Exception(
          pesanError(response, 'Registrasi kartu gagal'),
        );
      }

      if (!mounted) return;

      uidController.clear();
      setState(() {
        siswaTerpilih = null;
      });

      await muatData();

      if (!mounted) return;

      // Jangan mengakses siswaCocok.first setelah await/muatData.
      tampilkanPesan(
        'Kartu RFID berhasil didaftarkan untuk $namaSiswa.',
      );
    } catch (e) {
      tampilkanPesan(
        e.toString().replaceFirst('Exception: ', ''),
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<void> hapusRegistrasi(_KartuRfid kartu) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus Registrasi?'),
        content: Text(
          'Hapus kartu ${kartu.uid} dari ${kartu.nama}?\n\n'
          'Data kartu akan dihapus dari daftar registrasi. '
          'Riwayat absensi siswa tidak ikut dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (konfirmasi != true || !mounted) return;

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/kartu-rfid/${kartu.id}'),
        headers: await buildApiHeaders(),
      );

      if (response.statusCode != 200) {
        throw Exception(
          pesanError(response, 'Gagal menghapus registrasi kartu'),
        );
      }

      await muatData();
      if (!mounted) return;

      tampilkanPesan(
        'Registrasi kartu ${kartu.uid} berhasil dihapus.',
      );
    } catch (e) {
      tampilkanPesan(
        e.toString().replaceFirst('Exception: ', ''),
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final siswaTersedia = siswaTersediaUntukKelas;
    final kartuDaftar = kartuTampil;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Registrasi RFID',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF17365D),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Hubungkan kartu RFID dengan siswa dari kelas aktif.',
            style: TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 24),

          // STATUS PERANGKAT
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFE7F0FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Color(0xFF2563EB),
                  size: 28,
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mode Registrasi Manual',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF17365D),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Masukkan UID kartu yang sudah diketahui. '
                        'Pembacaan otomatis dari RFID reader '
                        'belum dihubungkan.',
                        style: TextStyle(color: Color(0xFF17365D)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFF4B8B8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gagal memuat data dari Laravel.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(errorMessage!),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: isLoading ? null : muatData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Coba Lagi'),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // FILTER KELAS UNTUK PILIHAN SISWA DAN DAFTAR KARTU.
          Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFE5EAF1)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final pilihanKelas = DropdownButtonFormField<String>(
                    key: ValueKey<String>(filterKelas),
                    initialValue: filterKelas,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Filter Kelas',
                      prefixIcon: const Icon(Icons.school_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: 'Semua Kelas',
                        child: Text('Semua Kelas'),
                      ),
                      ...daftarKelas.map(
                        (namaKelas) => DropdownMenuItem<String>(
                          value: namaKelas,
                          child: Text(namaKelas),
                        ),
                      ),
                    ],
                    onChanged: isLoading || isSaving || errorMessage != null
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              filterKelas = value;
                              siswaTerpilih = null;
                            });
                          },
                  );

                  if (constraints.maxWidth < 520) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pilih kelas untuk menyaring siswa dan kartu RFID.',
                          style: TextStyle(color: Colors.blueGrey),
                        ),
                        const SizedBox(height: 12),
                        pilihanKelas,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Filter Kelas',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Saring pilihan siswa dan daftar kartu berdasarkan kelas.',
                              style: TextStyle(
                                color: Colors.blueGrey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      SizedBox(width: 280, child: pilihanKelas),
                    ],
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 24),

          // FORM REGISTRASI
          if (isAdmin)
          Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFE5EAF1)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daftarkan Kartu Baru',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Pilih Siswa',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    key: ValueKey<int?>(siswaTerpilih),
                    initialValue: siswaTerpilih,
                    isExpanded: true,
                    decoration: InputDecoration(
                      hintText: isLoading
                          ? 'Memuat data siswa...'
                          : filterKelas == 'Semua Kelas'
                              ? 'Pilih siswa dari semua kelas'
                              : 'Pilih siswa kelas $filterKelas',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: siswaTersedia.map((siswa) {
                      return DropdownMenuItem<int>(
                        value: siswa.id,
                        child: Text(
                          '${siswa.nama} - ${siswa.nis} (${siswa.kelas})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: isLoading ||
                            isSaving ||
                            errorMessage != null
                        ? null
                        : (value) {
                            setState(() {
                              siswaTerpilih = value;
                            });
                          },
                  ),
                  if (!isLoading &&
                      errorMessage == null &&
                      siswaTersedia.isEmpty) ...[
                    const SizedBox(height: 8),
                     
                    Text(
                      filterKelas == 'Semua Kelas'
                          ? 'Semua siswa aktif sudah mempunyai kartu, atau belum ada siswa aktif.'
                          : 'Tidak ada siswa aktif tanpa kartu pada kelas $filterKelas.',
                      style: const TextStyle(
                        color: Colors.blueGrey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text(
                    'UID Kartu RFID',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: uidController,
                    enabled: !isLoading &&
                        !isSaving &&
                        errorMessage == null,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9a-fA-F\s:-]'),
                      ),
                    ],
                    decoration: InputDecoration(
                      hintText: 'Contoh: A1B2C3D4',
                      helperText:
                          'Untuk pengujian, UID dapat dimasukkan '
                          'secara manual.',
                      prefixIcon: const Icon(Icons.credit_card),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (value) {
                      final formatted = normalisasiUid(value);
                      if (formatted != value) {
                        uidController.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(
                            offset: formatted.length,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isLoading ||
                              isSaving ||
                              errorMessage != null
                          ? null
                          : simpanRegistrasi,
                      icon: isSaving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        isSaving ? 'Menyimpan...' : 'Simpan Registrasi',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // DAFTAR KARTU
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Kartu Terdaftar',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Muat ulang daftar kartu',
                onPressed: isLoading ? null : muatData,
                icon: const Icon(Icons.refresh),
              ),
              Chip(
                label: Text('${kartuDaftar.length} kartu'),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : errorMessage != null
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text('Daftar kartu belum dapat dimuat.'),
                        ),
                      )
                    : kartuDaftar.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.credit_card_off_outlined,
                                    size: 42,
                                    color: Colors.blueGrey,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    filterKelas == 'Semua Kelas'
                                        ? 'Belum ada kartu terdaftar.'
                                        : 'Belum ada kartu terdaftar untuk kelas $filterKelas.',
                                  ),
                                  const SizedBox(height: 5),
                                  const Text(
                                    'Daftarkan kartu pertama untuk '
                                    'memulai pengujian.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.blueGrey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('No.')),
                                DataColumn(label: Text('NIS')),
                                DataColumn(label: Text('Nama Siswa')),
                                DataColumn(label: Text('Kelas')),
                                DataColumn(label: Text('UID RFID')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('Aksi')),
                              ],
                              rows: List.generate(
                                kartuDaftar.length,
                                (index) {
                                  final kartu = kartuDaftar[index];

                                  return DataRow(
                                    cells: [
                                      DataCell(Text('${index + 1}')),
                                      DataCell(Text(kartu.nis)),
                                      DataCell(
                                        SizedBox(
                                          width: 180,
                                          child: Text(kartu.nama),
                                        ),
                                      ),
                                      DataCell(Text(kartu.kelas)),
                                      DataCell(
                                        Text(
                                          kartu.uid,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Chip(
                                          label: Text(
                                            kartu.aktif ? 'Aktif' : 'Nonaktif',
                                          ),
                                          backgroundColor: kartu.aktif
                                              ? const Color(0xFFE2F7E9)
                                              : const Color(0xFFFFE6E6),
                                          side: BorderSide.none,
                                        ),
                                      ),

                                      DataCell(
                                        isAdmin
                                            ? IconButton(
                                                tooltip: 'Hapus registrasi',
                                                onPressed: isSaving
                                                    ? null
                                                    : () => hapusRegistrasi(kartu),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.red,
                                                ),
                                              )
                                            : const SizedBox.shrink(),
                                      ),

                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Data registrasi disimpan di database SIPAS melalui Laravel API.',
            style: TextStyle(
              color: Colors.blueGrey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}