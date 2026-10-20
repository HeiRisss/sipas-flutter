import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_headers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color kelasNavy = Color(0xFF17365D);

const Color kelasBlue = Color(0xFF2563EB);

class _DataKelas {
  final int id;
  final String namaKelas;
  final String tingkat;
  final String tahunAjaran;
  final String waliKelas;
  final bool aktif;
  const _DataKelas({
    required this.id,
    required this.namaKelas,
    required this.tingkat,
    required this.tahunAjaran,
    required this.waliKelas,
    required this.aktif,
  });

  factory _DataKelas.fromJson(Map<String, dynamic> json) {
    final dynamic status = json['aktif'];
    return _DataKelas(
      id: int.parse(json['id'].toString()),
      namaKelas: json['nama_kelas']?.toString() ?? '',
      tingkat: json['tingkat']?.toString() ?? 'VII',
      tahunAjaran: json['tahun_ajaran']?.toString() ?? '',
      waliKelas: json['wali_kelas']?.toString() ?? '',
      aktif: status == true || status == 1 || status?.toString() == '1',
    );
  }
}

class KelasScreen extends StatefulWidget {
  const KelasScreen({super.key});

  @override
  State<KelasScreen> createState() => _KelasScreenState();
}

class _KelasScreenState extends State<KelasScreen> {
  static const String baseUrl = 'http://127.0.0.1:8000/api';

  List<_DataKelas> daftarKelas = [];

  bool isLoading = true;

  bool isSaving = false;
  String? errorMessage;

  @override

  void initState() {
    super.initState();
    muatKelas();
    muatRolePengguna();
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

  String pesanError(http.Response response, String defaultMessage) {
    try {
      final dynamic body = jsonDecode(response.body);
      if (body is Map) {
        final dynamic errors = body['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final dynamic first = errors.values.first;
          if (first is List && first.isNotEmpty) {
            return first.first.toString();
          }
        }
        if (body['message'] != null) {
          return body['message'].toString();
        }
      }
    } catch (_) {
      // Use fallback for non-JSON responses.
    }
    return '$defaultMessage (HTTP ${response.statusCode})';
  }

  Future<void> muatKelas() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/kelas'),
        headers: await buildApiHeaders(),
      );
      if (response.statusCode != 200) {
        throw Exception(pesanError(response, 'Gagal mengambil data kelas'));
      }
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw Exception('Format data kelas dari server tidak sesuai.');
      }
      final loaded = decoded
          .map<_DataKelas>((item) => _DataKelas.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList();
      if (!mounted) return;
      setState(() => daftarKelas = loaded);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void tampilkanPesan(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red.shade700 : null,
        ),
      );
  }

  Future<void> tampilkanForm({_DataKelas? kelas}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FormKelasDialog(kelas: kelas),
    );

    if (result == null || !mounted) return;

    await simpanKelas(
      data: result,
      kelas: kelas,
    );
  }

  Future<void> simpanKelas({
    required Map<String, dynamic> data,
    _DataKelas? kelas,
  }) async {
    if (isSaving) return;
    setState(() => isSaving = true);
    try {
      final bool tambah = kelas == null;
      final uri = Uri.parse(
        tambah ? '$baseUrl/kelas' : '$baseUrl/kelas/${kelas.id}',
      );
      final response = tambah
          ? await http.post(
              uri,
              headers: await buildApiHeaders(jsonBody: true),
              body: jsonEncode(data),
            )
          : await http.put(
              uri,
              headers: await buildApiHeaders(jsonBody: true),
              body: jsonEncode(data),
            );
      if ((tambah && response.statusCode != 201) ||
          (!tambah && response.statusCode != 200)) {
        throw Exception(
          pesanError(response, 'Gagal menyimpan data kelas'),
        );
      }
      await muatKelas();
      if (!mounted) return;
      tampilkanPesan(
        tambah ? 'Kelas berhasil ditambahkan.' : 'Data kelas berhasil diperbarui.',
      );
    } catch (e) {
      tampilkanPesan(
        e.toString().replaceFirst('Exception: ', ''),
        error: true,
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> ubahStatus(_DataKelas kelas) async {
    if (kelas.aktif && kelas.namaKelas == 'VII A') {
      tampilkanPesan(
        'VII A adalah kelas uji coba dengan data siswa yang sudah ada. '
        'Jangan nonaktifkan kelas ini pada tahap pengembangan.',
        error: true,
      );
      return;
    }
    final aktifBaru = !kelas.aktif;
    final setuju = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(aktifBaru ? 'Aktifkan Kelas?' : 'Nonaktifkan Kelas?'),
        content: Text(
          aktifBaru
              ? 'Aktifkan kembali kelas ${kelas.namaKelas}?'
              : 'Nonaktifkan kelas ${kelas.namaKelas}? Kelas tidak akan tersedia untuk pendaftaran siswa baru.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(aktifBaru ? 'Aktifkan' : 'Nonaktifkan'),
          ),
        ],
      ),
    );
    if (setuju != true || !mounted) return;
    setState(() => isSaving = true);
    try {
      final response = aktifBaru
          ? await http.put(
              Uri.parse('$baseUrl/kelas/${kelas.id}'),
              headers: await buildApiHeaders(jsonBody: true),
              body: jsonEncode({'aktif': true}),
            )
          : await http.delete(
              Uri.parse('$baseUrl/kelas/${kelas.id}'),
              headers: await buildApiHeaders(),
            );
      if (response.statusCode != 200) {
        throw Exception(
          pesanError(response, 'Gagal mengubah status kelas'),
        );
      }
      await muatKelas();
      if (!mounted) return;
      tampilkanPesan(
        aktifBaru ? 'Kelas berhasil diaktifkan.' : 'Kelas berhasil dinonaktifkan.',
      );
    } catch (e) {
      tampilkanPesan(
        e.toString().replaceFirst('Exception: ', ''),
        error: true,
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override

  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Data Kelas',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: kelasNavy,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Kelola kelas dan tahun ajaran siswa SMPN 1 Gambut.',
            style: TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE7F0FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: kelasBlue),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Kelas disimpan melalui Laravel API. Data siswa kelas VII A '
                    'yang sudah ada tetap dipertahankan.',
                    style: TextStyle(color: kelasNavy),
                  ),
                ),
              ],
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEEE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 10),
                  Expanded(child: Text(errorMessage!)),
                  TextButton(
                    onPressed: isLoading ? null : muatKelas,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total ${daftarKelas.length} kelas',
                  style: const TextStyle(color: Colors.blueGrey),
                ),
              ),
              IconButton(
                tooltip: 'Muat ulang',
                onPressed: isLoading || isSaving ? null : muatKelas,
                icon: const Icon(Icons.refresh),
              ),
              if (isAdmin) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: isLoading || isSaving
                    ? null
                    : () => tampilkanForm(),
                icon: const Icon(Icons.add),
                label: const Text('Tambah Kelas'),
              ),
            ],
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              color: Colors.white,
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFE5EAF1)),
              ),
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : errorMessage != null
                      ? const Center(
                          child: Text('Data kelas belum dapat dimuat.'),
                        )
                      : daftarKelas.isEmpty
                          ? const Center(
                              child: Text('Belum ada data kelas.'),
                            )
                          : SingleChildScrollView(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(
                                    const Color(0xFFF4F7FB),
                                  ),
                                  columns: const [
                                    DataColumn(label: Text('No.')),
                                    DataColumn(label: Text('Nama Kelas')),
                                    DataColumn(label: Text('Tingkat')),
                                    DataColumn(label: Text('Tahun Ajaran')),
                                    DataColumn(label: Text('Wali Kelas')),
                                    DataColumn(label: Text('Status')),
                                    DataColumn(label: Text('Aksi')),
                                  ],
                                  rows: List.generate(daftarKelas.length, (index) {
                                    final kelas = daftarKelas[index];
                                    return DataRow(
                                      cells: [
                                        DataCell(Text('${index + 1}')),
                                        DataCell(
                                          Text(
                                            kelas.namaKelas,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        DataCell(Text(kelas.tingkat)),
                                        DataCell(Text(
                                          kelas.tahunAjaran.isEmpty
                                              ? '-'
                                              : kelas.tahunAjaran,
                                        )),
                                        DataCell(Text(
                                          kelas.waliKelas.isEmpty
                                              ? '-'
                                              : kelas.waliKelas,
                                        )),
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: kelas.aktif
                                                  ? const Color(0xFFE2F7E9)
                                                  : const Color(0xFFFFE6E6),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              kelas.aktif ? 'Aktif' : 'Nonaktif',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: kelas.aktif
                                                    ? const Color(0xFF167447)
                                                    : Colors.red.shade700,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Row(
                                            children: [
                                              if (isAdmin)
                                              IconButton(
                                                tooltip: 'Edit kelas',
                                                onPressed: isSaving
                                                    ? null
                                                    : () => tampilkanForm(kelas: kelas),
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  color: kelasBlue,
                                                ),
                                              ),
                                              if (isAdmin)
                                              IconButton(
                                                tooltip: kelas.aktif
                                                    ? 'Nonaktifkan kelas'
                                                    : 'Aktifkan kelas',
                                                onPressed: isSaving
                                                    ? null
                                                    : () => ubahStatus(kelas),
                                                icon: Icon(
                                                  kelas.aktif
                                                      ? Icons.toggle_on_outlined
                                                      : Icons.toggle_off_outlined,
                                                  color: kelas.aktif
                                                      ? const Color(0xFF15945B)
                                                      : Colors.blueGrey,
                                                  size: 28,
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
          const SizedBox(height: 10),
          const Text(
            'Kelas VII A dilindungi sementara sebagai kelas uji coba.',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
}

class _FormKelasDialog extends StatefulWidget {
  final _DataKelas? kelas;
  const _FormKelasDialog({
    this.kelas,
  });

  @override
  State<_FormKelasDialog> createState() =>
      _FormKelasDialogState();
}

class _FormKelasDialogState extends State<_FormKelasDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController namaController;
  late final TextEditingController tahunController;
  late final TextEditingController waliController;
  late String tingkat;

  @override

  void initState() {
    super.initState();
    final kelas = widget.kelas;
    namaController = TextEditingController(
      text: kelas?.namaKelas ?? '',
    );
    tahunController = TextEditingController(
      text: kelas?.tahunAjaran.isNotEmpty == true
          ? kelas!.tahunAjaran
          : '2026/2027',
    );
    waliController = TextEditingController(
      text: kelas?.waliKelas ?? '',
    );
    tingkat = kelas?.tingkat ?? 'VII';
  }

  @override

  void dispose() {
    namaController.dispose();
    tahunController.dispose();
    waliController.dispose();
    super.dispose();
  }

  @override

  Widget build(BuildContext context) {
    final kelas = widget.kelas;
    return AlertDialog(
      title: Text(
        kelas == null ? 'Tambah Kelas' : 'Edit Kelas',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: namaController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Kelas',
                    hintText: 'Contoh: VII B',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nama kelas wajib diisi.';
                    }
                    if (value.trim().length > 20) {
                      return 'Nama kelas maksimal 20 karakter.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: tingkat,
                  decoration: const InputDecoration(
                    labelText: 'Tingkat',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'VII',
                      child: Text('VII'),
                    ),
                    DropdownMenuItem(
                      value: 'VIII',
                      child: Text('VIII'),
                    ),
                    DropdownMenuItem(
                      value: 'IX',
                      child: Text('IX'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => tingkat = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: tahunController,
                  decoration: const InputDecoration(
                    labelText: 'Tahun Ajaran',
                    hintText: '2026/2027',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isNotEmpty &&
                        !RegExp(r'^\d{4}/\d{4}$').hasMatch(text)) {
                      return 'Gunakan format YYYY/YYYY.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: waliController,
                  decoration: const InputDecoration(
                    labelText: 'Wali Kelas (opsional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (kelas != null) ...[
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Status aktif/nonaktif diatur dari tabel kelas.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            if (!(formKey.currentState?.validate() ?? false)) {
              return;
            }
            Navigator.pop(
              context,
              <String, dynamic>{
                'nama_kelas': namaController.text.trim(),
                'tingkat': tingkat,
                'tahun_ajaran': tahunController.text.trim().isEmpty
                    ? null
                    : tahunController.text.trim(),
                'wali_kelas': waliController.text.trim().isEmpty
                    ? null
                    : waliController.text.trim(),
              },
            );
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}