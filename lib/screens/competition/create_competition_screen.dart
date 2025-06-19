import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class CreateCompetitionScreen extends StatefulWidget {
  const CreateCompetitionScreen({super.key});

  @override
  State<CreateCompetitionScreen> createState() =>
      _CreateCompetitionScreenState();
}

class _CreateCompetitionScreenState extends State<CreateCompetitionScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _registrationStartController =
      TextEditingController();
  final TextEditingController _registrationEndController =
      TextEditingController();
  bool? _elimination;
  String? _selectedVenue;
  String? _customDistance;
  List<String> _selectedBowTypes = [];
  final List<String> _selectedAgeGroups = [];
  final List<String> _selectedDistances = [];

  // Yaş grupları ve mesafeler güncellendi
  final List<String> _ageGroups = [
    '9-10 Yaş',
    '11-12 Yaş',
    '13-14 Yaş',
    'U18 (15-16-17)',
    'U21 (18-19-20)',
    'Büyükler',
  ];
  final List<String> _distances = [
    '18',
    '20',
    '30',
    '50',
    '60',
    '70',
    'Custom'
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.createCompetitionTitle),
      ),
      body: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom, left: 24.0, right: 24.0, top: 24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.createCompetitionTitle,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.competitionNameLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descController,
                decoration: InputDecoration(
                  labelText: l10n.competitionDescriptionLabel,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _dateController,
                decoration: InputDecoration(
                  labelText: l10n.competitionDateLabel,
                  border: const OutlineInputBorder(),
                  hintText: l10n.competitionDateHint,
                ),
                readOnly: true,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    _dateController.text =
                        '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                  }
                },
              ),
              const SizedBox(height: 16),
              // Yay tipi seçimi (çoklu seçim)
              Text('Yay Tipi',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Hepsi'),
                    selected: _selectedBowTypes.length == 3,
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedBowTypes = [
                            'recurve',
                            'compound',
                            'barebow'
                          ];
                        } else {
                          _selectedBowTypes.clear();
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Recurve'),
                    selected: _selectedBowTypes.contains('recurve'),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedBowTypes.add('recurve');
                        } else {
                          _selectedBowTypes.remove('recurve');
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Compound'),
                    selected: _selectedBowTypes.contains('compound'),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedBowTypes.add('compound');
                        } else {
                          _selectedBowTypes.remove('compound');
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Barebow'),
                    selected: _selectedBowTypes.contains('barebow'),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedBowTypes.add('barebow');
                        } else {
                          _selectedBowTypes.remove('barebow');
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Yaş grupları çoklu seçim
              Text(l10n.competitionAgeGroupsLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: Text(l10n.competitionAgeGroup1),
                    selected:
                        _selectedAgeGroups.contains(l10n.competitionAgeGroup1),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedAgeGroups.add(l10n.competitionAgeGroup1);
                        } else {
                          _selectedAgeGroups.remove(l10n.competitionAgeGroup1);
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: Text(l10n.competitionAgeGroup2),
                    selected:
                        _selectedAgeGroups.contains(l10n.competitionAgeGroup2),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedAgeGroups.add(l10n.competitionAgeGroup2);
                        } else {
                          _selectedAgeGroups.remove(l10n.competitionAgeGroup2);
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: Text(l10n.competitionAgeGroup3),
                    selected:
                        _selectedAgeGroups.contains(l10n.competitionAgeGroup3),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedAgeGroups.add(l10n.competitionAgeGroup3);
                        } else {
                          _selectedAgeGroups.remove(l10n.competitionAgeGroup3);
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: Text(l10n.competitionAgeGroup4),
                    selected:
                        _selectedAgeGroups.contains(l10n.competitionAgeGroup4),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedAgeGroups.add(l10n.competitionAgeGroup4);
                        } else {
                          _selectedAgeGroups.remove(l10n.competitionAgeGroup4);
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: Text(l10n.competitionAgeGroup5),
                    selected:
                        _selectedAgeGroups.contains(l10n.competitionAgeGroup5),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedAgeGroups.add(l10n.competitionAgeGroup5);
                        } else {
                          _selectedAgeGroups.remove(l10n.competitionAgeGroup5);
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: Text(l10n.competitionAgeGroup6),
                    selected:
                        _selectedAgeGroups.contains(l10n.competitionAgeGroup6),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedAgeGroups.add(l10n.competitionAgeGroup6);
                        } else {
                          _selectedAgeGroups.remove(l10n.competitionAgeGroup6);
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Mesafeler çoklu seçim
              Text(l10n.competitionDistancesLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: Text(l10n.competitionDistance18),
                    selected: _selectedDistances.contains('18'),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedDistances.add('18');
                        } else {
                          _selectedDistances.remove('18');
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: Text(l10n.competitionDistance20),
                    selected: _selectedDistances.contains('20'),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedDistances.add('20');
                        } else {
                          _selectedDistances.remove('20');
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: Text(l10n.competitionDistance30),
                    selected: _selectedDistances.contains('30'),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedDistances.add('30');
                        } else {
                          _selectedDistances.remove('30');
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: Text(l10n.competitionDistance50),
                    selected: _selectedDistances.contains('50'),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedDistances.add('50');
                        } else {
                          _selectedDistances.remove('50');
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: Text(l10n.competitionDistance60),
                    selected: _selectedDistances.contains('60'),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedDistances.add('60');
                        } else {
                          _selectedDistances.remove('60');
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: Text(l10n.competitionDistance70),
                    selected: _selectedDistances.contains('70'),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedDistances.add('70');
                        } else {
                          _selectedDistances.remove('70');
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: Text(l10n.competitionDistanceCustom),
                    selected: _selectedDistances.contains('Custom'),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedDistances.add('Custom');
                        } else {
                          _selectedDistances.remove('Custom');
                          _customDistance = null;
                        }
                      });
                    },
                  ),
                ],
              ),
              if (_selectedDistances.contains('Custom')) ...[
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    labelText: l10n.competitionCustomDistance,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    setState(() {
                      _customDistance = val;
                    });
                  },
                ),
              ],
              const SizedBox(height: 16),
              // Mekan seçimi
              Text(l10n.competitionVenueLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Radio<String>(
                    value: 'Indoor',
                    groupValue: _selectedVenue,
                    onChanged: (val) {
                      setState(() {
                        _selectedVenue = val;
                      });
                    },
                  ),
                  Text(l10n.competitionVenueIndoor),
                  const SizedBox(width: 16),
                  Radio<String>(
                    value: 'Outdoor',
                    groupValue: _selectedVenue,
                    onChanged: (val) {
                      setState(() {
                        _selectedVenue = val;
                      });
                    },
                  ),
                  Text(l10n.competitionVenueOutdoor),
                ],
              ),
              const SizedBox(height: 16),
              // Eleme olacak mı? (evet/hayır)
              Row(
                children: [
                  Text(l10n.eliminationQuestion,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 16),
                  StatefulBuilder(
                    builder: (context, setStateSB) {
                      return Switch(
                        value: _elimination ?? false,
                        onChanged: (val) {
                          setStateSB(() {
                            setState(() {
                              _elimination = val;
                            });
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(_elimination == true
                      ? l10n.eliminationYes
                      : l10n.eliminationNo),
                ],
              ),
              const SizedBox(height: 16),
              // Kayıt tarihleri
              Text(l10n.registrationDatesLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _registrationStartController,
                      decoration: InputDecoration(
                        labelText: l10n.registrationStartLabel,
                        border: const OutlineInputBorder(),
                        hintText: l10n.competitionDateHint,
                      ),
                      readOnly: true,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          _registrationStartController.text =
                              '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _registrationEndController,
                      decoration: InputDecoration(
                        labelText: l10n.registrationEndLabel,
                        border: const OutlineInputBorder(),
                        hintText: l10n.competitionDateHint,
                      ),
                      readOnly: true,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          _registrationEndController.text =
                              '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    // Kaydet fonksiyonu ileride eklenecek
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(l10n.competitionSaveButton +
                              ' özelliği yakında!')),
                    );
                  },
                  child: Text(l10n.competitionSaveButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
