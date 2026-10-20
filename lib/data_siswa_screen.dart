import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_headers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Siswa {
  final int id;
  final String nis;
  final String nama;
  final String kelas;
  final String uid;
  final bool aktif;

  const Siswa({
    required this.id,
    required this.nis,
    required this.nama,
    required this.kelas,
    this.uid = '-',
    this.aktif = true,
  });

  factory Siswa.fromJson(Map<String, dynamic> json) {
    final kartu = json['kartu_rfid'];
    final uidKartu = kartu is Map ? kartu['uid']?.toString() : null;
    final statusAktif = json['aktif'];

    return Siswa(
      id: int.parse(json['id'].toString()),
      nis: json['nis']?.toString() ?? '',
      nama: json['nama']?.toString() ?? '',
      kelas: json['kelas']?.toString() ?? '',
      uid: uidKartu == null || uidKartu.isEmpty ? '-' : uidKartu,
      aktif: statusAktif == true ||
          statusAktif == 1 ||
          statusAktif?.toString() == '1',
    );
  }
}

class DataSiswaScreen extends StatefulWidget {
  const DataSiswaScreen({super.key});

  @override
  State<DataSiswaScreen> createState() => _DataSiswaScreenState();
}

class _DataSiswaScreenState extends State<DataSiswaScreen> {
  static const String baseUrl = 'http://127.0.0.1:8000/api';
  static const String semuaKelasValue = '__SEMUA_KELAS__';

  final TextEditingController searchController = TextEditingController();

  List<Siswa> siswaList = [];
  List<String> kelasList = [];

  String kataKunci = '';
  String filterKelas = semuaKelasValue;
  String? errorMessage;
  bool isLoading = true;
  bool isSaving = false;
  bool isAdmin = false;

  @override
  void initState() {
    super.initState();
    muatDataSiswa();
    muatRolePengguna();
  }
  Future<void> muatRolePengguna() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('sipas_user_role') ?? '';

    if (!mounted) return;

    setState(() {
      isAdmin = role.toLowerCase() == 'admin';
    });
  }
  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  String pesanError(http.Response response, String pesanDefault) {
    try {
      final dynamic hasil = jsonDecode(response.body);

      if (hasil is Map) {
        final errors = hasil['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final pesan = errors.values.first;
          if (pesan is List && pesan.isNotEmpty) {
            return pesan.first.toString();
          }
        }

        if (hasil['message'] != null) {
          return hasil['message'].toString();
        }
      }
    } catch (_) {
      // Respons bukan JSON; gunakan pesan default.
    }

    return '$pesanDefault (HTTP ${response.statusCode})';
  }

  Future<void> muatDataSiswa() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final responses = await Future.wait([
        http.get(
          Uri.parse('$baseUrl/siswa'),
          headers: await buildApiHeaders(),
        ),
        http.get(
          Uri.parse('$baseUrl/kelas?aktif=1'),
          headers: await buildApiHeaders(),
        ),
      ]);

      final siswaResponse = responses[0];
      final kelasResponse = responses[1];

      if (siswaResponse.statusCode != 200) {
        throw Exception(
          pesanError(siswaResponse, 'Gagal mengambil data siswa'),
        );
      }

      if (kelasResponse.statusCode != 200) {
        throw Exception(
          pesanError(kelasResponse, 'Gagal mengambil daftar kelas'),
        );
      }

      final dynamic hasilSiswa = jsonDecode(siswaResponse.body);
      final dynamic hasilKelas = jsonDecode(kelasResponse.body);

      if (hasilSiswa is! List || hasilKelas is! List) {
        throw Exception('Format data dari server tidak sesuai.');
      }

      final dataBaru = hasilSiswa.map<Siswa>((item) {
        return Siswa.fromJson(Map<String, dynamic>.from(item as Map));
      }).toList();

      final kelasBaru = hasilKelas
          .map<String>((item) {
            final kelas = Map<String, dynamic>.from(item as Map);
            return kelas['nama_kelas']?.toString() ?? '';
          })
          .where((nama) => nama.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      if (!mounted) return;

      setState(() {
        siswaList = dataBaru;
        kelasList = kelasBaru;

        if (filterKelas != semuaKelasValue &&
            !kelasList.contains(filterKelas)) {
          filterKelas = semuaKelasValue;
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

  List<Siswa> get siswaTampil {
    final kata = kataKunci.toLowerCase().trim();

    return siswaList.where((siswa) {
      final cocokPencarian = siswa.nama.toLowerCase().contains(kata) ||
          siswa.nis.toLowerCase().contains(kata);
      final cocokKelas = filterKelas == semuaKelasValue ||
          siswa.kelas == filterKelas;

      return cocokPencarian && cocokKelas;
    }).toList();
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

  Future<void> tampilkanForm({Siswa? siswa}) async {
    if (kelasList.isEmpty) {
      tampilkanPesan(
        'Belum ada kelas aktif. Tambahkan kelas terlebih dahulu.',
        error: true,
      );
      return;
    }

    final nisController = TextEditingController(text: siswa?.nis ?? '');
    final namaController = TextEditingController(text: siswa?.nama ?? '');
    final formKey = GlobalKey<FormState>();

    // Saat mengedit, gunakan kelas siswa jika masih aktif.
    // Jika kelas lamanya nonaktif, pilih kelas aktif pertama.
    String? kelasDipilih = kelasList.contains(siswa?.kelas)
        ? siswa!.kelas
        : kelasList.first;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (contextDialog, setDialogState) {
              return AlertDialog(
                title: Text(siswa == null ? 'Tambah Siswa' : 'Edit Siswa'),
                content: SizedBox(
                  width: 420,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            controller: nisController,
                            decoration: const InputDecoration(
                              labelText: 'NIS',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'NIS wajib diisi.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: namaController,
                            decoration: const InputDecoration(
                              labelText: 'Nama Siswa',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Nama siswa wajib diisi.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            key: ValueKey(kelasDipilih),
                            initialValue: kelasDipilih,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Kelas',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.school_outlined),
                            ),
                            items: kelasList.map((namaKelas) {
                              return DropdownMenuItem<String>(
                                value: namaKelas,
                                child: Text(namaKelas),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() {
                                kelasDipilih = value;
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Pilih kelas aktif tempat siswa terdaftar.',
                              style: TextStyle(
                                color: Colors.blueGrey,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () => Navigator.pop(dialogContext),
                    child: const Text('Batal'),
                  ),
                  FilledButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (!(formKey.currentState?.validate() ?? false)) {
                              return;
                            }
                            if (kelasDipilih == null) {
                              tampilkanPesan(
                                'Pilih kelas terlebih dahulu.',
                                error: true,
                              );
                              return;
                            }

                            await simpanSiswa(
                              siswa: siswa,
                              nis: nisController.text.trim(),
                              nama: namaController.text.trim(),
                              kelas: kelasDipilih!,
                              dialogContext: dialogContext,
                            );
                          },
                    child: Text(isSaving ? 'Menyimpan...' : 'Simpan'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      nisController.dispose();
      namaController.dispose();
    }
  }

  Future<void> simpanSiswa({
    required String nis,
    required String nama,
    required String kelas,
    required BuildContext dialogContext,
    Siswa? siswa,
  }) async {
    if (isSaving) return;

    final nisDuplikat = siswaList.any((item) {
      return item.nis.toLowerCase() == nis.toLowerCase() &&
          item.id != siswa?.id;
    });

    if (nisDuplikat) {
      tampilkanPesan('NIS tersebut sudah digunakan.', error: true);
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final tambah = siswa == null;
      final uri = Uri.parse(
        tambah ? '$baseUrl/siswa' : '$baseUrl/siswa/${siswa.id}',
      );
      final body = jsonEncode({
        'nis': nis,
        'nama': nama,
        'kelas': kelas,
      });

      final response = tambah
        ? await http.post(
            uri,
            headers: await buildApiHeaders(jsonBody: true),
            body: body,
          )
        : await http.put(
            uri,
            headers: await buildApiHeaders(jsonBody: true),
            body: body,
          );

      final statusBerhasil =
          tambah ? response.statusCode == 201 : response.statusCode == 200;

      if (!statusBerhasil) {
        throw Exception(
          pesanError(response, 'Gagal menyimpan data siswa'),
        );
      }

      if (!mounted || !dialogContext.mounted) return;

      Navigator.of(dialogContext).pop();
      await muatDataSiswa();

      if (!mounted) return;
      tampilkanPesan(
        tambah
            ? 'Siswa berhasil ditambahkan ke database.'
            : 'Data siswa berhasil diperbarui.',
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

  Future<void> hapusSiswa(Siswa siswa) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Nonaktifkan Siswa?'),
          content: Text(
            'Nonaktifkan ${siswa.nama}? '
            'Data siswa dan riwayatnya tetap tersimpan di database.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Nonaktifkan'),
            ),
          ],
        );
      },
    );

    if (konfirmasi != true || !mounted) return;

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/siswa/${siswa.id}'),
        headers: await buildApiHeaders(),
      );

      if (response.statusCode != 200) {
        throw Exception(
          pesanError(response, 'Gagal menonaktifkan siswa'),
        );
      }

      await muatDataSiswa();
      if (!mounted) return;
      tampilkanPesan('Siswa berhasil dinonaktifkan.');
    } catch (e) {
      tampilkanPesan(
        e.toString().replaceFirst('Exception: ', ''),
        error: true,
      );
    }
  }

  Widget dropdownFilterKelas() {
    return SizedBox(
      width: 210,
      child: DropdownButtonFormField<String>(
        key: ValueKey(filterKelas),
        initialValue: filterKelas,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Filter Kelas',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        items: [
          const DropdownMenuItem<String>(
            value: semuaKelasValue,
            child: Text('Semua Kelas'),
          ),
          ...kelasList.map((namaKelas) {
            return DropdownMenuItem<String>(
              value: namaKelas,
              child: Text(namaKelas),
            );
          }),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            filterKelas = value;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = siswaTampil;

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Data Siswa',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF17365D),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Kelola data siswa dan kelas masing-masing.',
            style: TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final search = TextField(
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );

              final controls = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Muat ulang data',
                    onPressed: isLoading ? null : muatDataSiswa,
                    icon: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 4),
                  if (isAdmin)
                  FilledButton.icon(
                    onPressed: isLoading || isSaving || kelasList.isEmpty
                        ? null
                        : () => tampilkanForm(),
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah Siswa'),
                  ),
                ],
              );

              if (constraints.maxWidth < 850) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    search,
                    const SizedBox(height: 10),
                    dropdownFilterKelas(),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: controls,
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: search),
                      const SizedBox(width: 12),
                      controls,
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      dropdownFilterKelas(),
                      const Spacer(),
                      Text(
                        'Kelas aktif: ${kelasList.length}',
                        style: const TextStyle(color: Colors.blueGrey),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Text(
            'Menampilkan ${data.length} dari ${siswaList.length} siswa aktif',
            style: const TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.cloud_off_outlined,
                                size: 48,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Gagal memuat data dari Laravel.',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                errorMessage!,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: muatDataSiswa,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Coba Lagi'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Card(
                        color: Colors.white,
                        elevation: 0,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE5EAF1)),
                        ),
                        child: data.isEmpty
                            ? const Center(
                                child: Text(
                                  'Tidak ada data siswa yang cocok.',
                                ),
                              )
                            : SingleChildScrollView(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columns: const [
                                      DataColumn(label: Text('No.')),
                                      DataColumn(label: Text('NIS')),
                                      DataColumn(label: Text('Nama Siswa')),
                                      DataColumn(label: Text('Kelas')),
                                      DataColumn(label: Text('UID RFID')),
                                      DataColumn(label: Text('Aksi')),
                                    ],
                                    rows: List.generate(data.length, (index) {
                                      final siswa = data[index];

                                      return DataRow(
                                        cells: [
                                          DataCell(Text('${index + 1}')),
                                          DataCell(Text(siswa.nis)),
                                          DataCell(
                                            SizedBox(
                                              width: 190,
                                              child: Text(siswa.nama),
                                            ),
                                          ),
                                          DataCell(Text(siswa.kelas)),
                                          DataCell(Text(siswa.uid)),
                                          DataCell(
                                            Row(
                                              children: [
                                                if (isAdmin)
                                                  IconButton(
                                                    tooltip: 'Edit',
                                                    onPressed: isSaving
                                                        ? null
                                                        : () => tampilkanForm(
                                                            siswa: siswa,
                                                          ),
                                                    icon: const Icon(
                                                      Icons.edit_outlined,
                                                      color: Color(0xFF2563EB),
                                                    ),
                                                  ),
                                                if (isAdmin)
                                                  IconButton(
                                                    tooltip: 'Nonaktifkan',
                                                    onPressed: isSaving
                                                        ? null
                                                        : () => hapusSiswa(siswa),
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                  ),
                                ),
                              ),
                      ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Data siswa dan kelas disimpan melalui Laravel API.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blueGrey,
            ),
          ),
        ],
      ),
    );
  }
}