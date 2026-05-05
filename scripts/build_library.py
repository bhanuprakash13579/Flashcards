#!/usr/bin/env python3
"""
build_library.py
────────────────
Reads all JSON files from ~/Desktop/static_gk/**/*.json and
~/Desktop/Flashcards/epfo_flashcards.json, then:

1. Groups static_gk questions into smart chapters per subject
2. Auto-classifies each question's type (arithmetic / reasoning / verbal /
   legal / science / factual) and assigns a timeLimitSeconds
3. Writes one BackupFile-format JSON per subject into
   Sources/Resources/Library/
4. Writes a library_manifest.json index file
5. Enriches epfo_flashcards.json with chapter / chapterName /
   questionType / timeLimitSeconds and writes epfo_flashcards_v2.json
"""

import json, os, glob, re, uuid, hashlib
from datetime import datetime, timezone
from collections import defaultdict

# ─── Paths ───────────────────────────────────────────────────────────────────
STATIC_GK_DIR  = os.path.expanduser("~/Desktop/static_gk")
EPFO_JSON      = os.path.expanduser("~/Desktop/Flashcards/epfo_flashcards.json")
OUT_DIR        = os.path.expanduser("~/Desktop/Flashcards/Sources/Resources/Library")
os.makedirs(OUT_DIR, exist_ok=True)

NOW_ISO = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# ─── Subject definitions ──────────────────────────────────────────────────────
# Each entry: (canonical_name, display_name, sf_icon, color_hex,
#              [source_subjects], [(chapter_name, [tc_prefix_patterns])])
#
# tc_prefix_patterns: topic_code must START WITH one of these strings
# (case-insensitive comparison after stripping trailing _)

SUBJECTS = [
    {
        "id": "indian_polity",
        "name": "Indian Polity",
        "icon": "building.columns.fill",
        "color": "#E07820",
        "sources": ["Polity"],
        "chapters": [
            ("Constitution & Preamble",      ["POL_PREAMBLE", "POL_CONSTITUTION", "POL_SCHEDULES",
                                               "POL_CITIZENSHIP", "POL_AMENDMENTS"]),
            ("Fundamental Rights",            ["POL_FR", "POL_FUNDAMENTAL_RIGHTS",
                                               "POL_FUND_RIGHTS", "POL_NCERT_BASIC_RIGHTS"]),
            ("Directive Principles & Duties", ["POL_DPSP", "POL_FUNDAMENTAL_DUTIES"]),
            ("Parliament",                    ["POL_PARLIAMENT", "POL_LOK_SABHA",
                                               "POL_RAJYA_SABHA", "POL_MONEY_BILL", "POL_FINANCE_BILL"]),
            ("President & Vice President",    ["POL_PRESIDENT", "POL_VP", "POL_PRESIDENTIAL"]),
            ("Prime Minister & Cabinet",      ["POL_PM_COM", "POL_PRIME_MINISTER"]),
            ("Judiciary",                     ["POL_SC", "POL_HC", "POL_CHIEF_JUSTICE",
                                               "POL_JUDICIARY", "POL_HIGH_COURT", "POL_SUPREME_COURT"]),
            ("State Government",              ["POL_GOVERNOR", "POL_CHIEF_MINISTER",
                                               "POL_STATE_LEGISLATURE"]),
            ("Constitutional Bodies",         ["POL_CAG", "POL_ELECTION_COM",
                                               "POL_ELECTION_COMMISSION", "POL_ELECTION_REFORMS",
                                               "POL_AG", "POL_ATTORNEY_GENERAL",
                                               "POL_SOLICITOR_GENERAL",
                                               "POL_CONSTITUTIONAL_OFFICES", "POL_NHRC_NCW"]),
            ("Emergency & Anti-Defection",    ["POL_EMERGENCY", "POL_ANTI_DEFECTION"]),
            ("Local Self-Government",         ["POL_PANCHAYATI_RAJ", "POL_MUNICIPALITIES",
                                               "POL_LOCAL_GOVT"]),
            ("Miscellaneous",                 ["POL_NITI", "POL_FINANCE_COM",
                                               "POL_GST_COUNCIL", "POL_RTI", "POL_MIXED"]),
        ],
    },
    {
        "id": "indian_history",
        "name": "Indian History",
        "icon": "scroll.fill",
        "color": "#A0522D",
        "sources": ["History"],
        "chapters": [
            ("Ancient India",                 ["HIS_INDUS", "HIS_VEDIC", "HIS_MAURYA",
                                               "HIS_POST_MAURYA", "HIS_GUPTA", "HIS_HARYANKA",
                                               "HIS_HARSHA", "HIS_SANGAM", "HIS_ANCIENT",
                                               "HIS_ASHOKAN"]),
            ("Buddhism & Jainism",            ["HIS_BUDDHA", "HIS_BUDDHISM", "HIS_JAINISM"]),
            ("South India & Regional Kingdoms",["HIS_CHOLA", "HIS_VIJAYANAGAR",
                                               "HIS_ANCIENT_SOUTH", "HIS_RAJPUT"]),
            ("Medieval India & Delhi Sultanate",["HIS_DELHI_SULT", "HIS_KHILJI",
                                               "HIS_LODI", "HIS_MEDIEVAL"]),
            ("Mughal Empire",                 ["HIS_MUGHAL", "HIS_AKBAR", "HIS_BABUR",
                                               "HIS_AURANGZEB", "HIS_JAHANGIR", "HIS_SHAH_JAHAN"]),
            ("Bhakti, Sufi & Social Reform",  ["HIS_BHAKTI", "HIS_SUFI",
                                               "HIS_SOCIAL_REFORMERS", "HIS_RAJA_RAM",
                                               "HIS_VIVEKANANDA"]),
            ("Maratha & Later Rulers",        ["HIS_MARATHA", "HIS_MAHARANA", "HIS_TIPU",
                                               "HIS_EUROPEANS", "HIS_PORTUGUESE", "HIS_PESHWA",
                                               "HIS_SHIVAJI"]),
            ("British India",                 ["HIS_BRITISH", "HIS_REVOLT", "HIS_VICEROYS",
                                               "HIS_LAND_REVENUE"]),
            ("Freedom Movement",              ["HIS_GANDHI", "HIS_INC", "HIS_FREEDOM",
                                               "HIS_NON_COOPERATION", "HIS_QUIT",
                                               "HIS_ROUND_TABLE", "HIS_INDIA_INDEPENDENCE",
                                               "HIS_NATIONALIST", "HIS_FREEDOM_FIGHTERS"]),
            ("Art, Culture & Post-Independence",["HIS_ARCHITECTURE", "HIS_INDIAN_FILMS",
                                               "HIS_WORLD", "HIS_POST_INDEPENDENCE"]),
        ],
    },
    {
        "id": "indian_geography",
        "name": "Indian Geography",
        "icon": "map.fill",
        "color": "#2D7A4F",
        "sources": ["Geography"],
        "chapters": [
            ("Physical Features",             ["GEO_IND_HIMALAYAS", "GEO_IND_PHYSICAL",
                                               "GEO_INDIAN_MOUNTAINS", "GEO_INDIAN_DESERTS",
                                               "GEO_INDIAN_PASSES", "GEO_INDIAN_ISLANDS",
                                               "GEO_VOLCANOES"]),
            ("Rivers & Water Bodies",         ["GEO_IND_RIVERS", "GEO_IND_RIVER",
                                               "GEO_HIMALAYAN_RIVERS", "GEO_PENINSULAR_RIVERS",
                                               "GEO_INDIAN_RIVERS", "GEO_HIMALAYAN_GLACIERS",
                                               "GEO_INDIAN_LAKES", "GEO_LAKES",
                                               "GEO_INDIAN_DAMS", "GEO_INDIAN_WATERFALLS"]),
            ("Climate & Monsoon",             ["GEO_CLIMATE", "GEO_INDIAN_CLIMATE",
                                               "GEO_INDIAN_MONSOON", "GEO_IND_MONSOON",
                                               "GEO_WINDS"]),
            ("Soils, Forests & Biodiversity", ["GEO_INDIAN_SOILS", "GEO_INDIAN_FORESTS",
                                               "GEO_IND_FORESTS", "GEO_BIOSPHERE",
                                               "GEO_TIGER_RESERVES", "GEO_NATIONAL_PARKS",
                                               "GEO_NORTH_EAST"]),
            ("Agriculture & Industry",        ["GEO_IND_AGRI", "GEO_INDIAN_AGRICULTURE",
                                               "GEO_SOIL_AGRI", "GEO_AGRICULTURE_INDIA",
                                               "GEO_INDIAN_INDUSTRIES", "GEO_INDIAN_PORTS",
                                               "GEO_IND_ECONOMIC"]),
            ("Minerals & Resources",          ["GEO_IND_MINERALS", "GEO_ROCKS_MINERALS"]),
            ("World Geography",               ["GEO_WORLD", "GEO_OCEAN", "GEO_AFRICAN",
                                               "GEO_LATITUDES", "GEO_SOLAR", "GEO_RIVERS_WORLD"]),
            ("Indian Tribes & People",        ["GEO_INDIAN_TRIBES"]),
        ],
    },
    {
        "id": "indian_economy",
        "name": "Indian Economy",
        "icon": "chart.line.uptrend.xyaxis",
        "color": "#1565C0",
        "sources": ["Economics"],
        "chapters": [
            ("GDP & National Income",         ["ECO_GDP", "ECO_NATIONAL_INCOME", "ECO_SECTORS",
                                               "ECO_MIXED"]),
            ("Banking & RBI",                 ["ECO_BANKING", "ECO_RBI", "ECO_MONEY",
                                               "ECO_MONETARY_POLICY"]),
            ("Budget, Taxes & Fiscal Policy", ["ECO_BUDGET", "ECO_FISCAL_POLICY",
                                               "ECO_PUBLIC_FINANCE", "ECO_DIRECT_TAXES",
                                               "ECO_INDIRECT_TAXES", "ECO_GST", "ECO_TAXES",
                                               "ECO_FINANCE_COMMISSION"]),
            ("Inflation & Markets",           ["ECO_INFLATION", "ECO_MARKETS",
                                               "ECO_STOCK_MARKETS"]),
            ("Planning & Poverty",            ["ECO_PLANNING", "ECO_FIVE_YEAR_PLANS",
                                               "ECO_NITI_AAYOG", "ECO_POVERTY"]),
            ("Agriculture & Schemes",         ["ECO_AGRICULTURE", "ECO_SCHEMES"]),
            ("Trade & International Finance", ["ECO_FOREIGN_TRADE", "ECO_BOP", "ECO_WTO",
                                               "ECO_WORLD_BODIES", "ECO_ORGANISATIONS",
                                               "ECO_TRADE"]),
            ("Insurance & Miscellaneous",     ["ECO_INSURANCE"]),
        ],
    },
    {
        "id": "biology",
        "name": "Biology",
        "icon": "leaf.fill",
        "color": "#27AE60",
        "sources": ["Biology"],
        "chapters": [
            ("Cell Biology & Genetics",       ["BIO_CELL", "BIO_DNA", "BIO_GENETICS",
                                               "BIO_HEREDITY", "BIO_EVOLUTION"]),
            ("Digestion & Nutrition",         ["BIO_DIGESTION", "BIO_DIGESTIVE",
                                               "BIO_NUTRITION", "BIO_LIVER_PANCREAS"]),
            ("Circulatory System",            ["BIO_CIRCULATION", "BIO_HEART", "BIO_BLOOD"]),
            ("Respiratory System",            ["BIO_RESPIRATION", "BIO_LUNGS",
                                               "BIO_RESPIRATORY", "BIO_RESPIRATION_PHOTOSYNTHESIS"]),
            ("Nervous & Endocrine Systems",   ["BIO_NERVOUS", "BIO_NEURONS", "BIO_BRAIN",
                                               "BIO_ENDOCRINE", "BIO_HORMONES_HUMAN",
                                               "BIO_ENZYMES"]),
            ("Excretion & Reproduction",      ["BIO_EXCRETION", "BIO_KIDNEY",
                                               "BIO_BONES", "BIO_REPRODUCTION",
                                               "BIO_REPRODUCTIVE"]),
            ("Plant Biology",                 ["BIO_PLANT", "BIO_PHOTOSYNTHESIS",
                                               "BIO_HORMONES_PLANT"]),
            ("Microbes, Diseases & Immunity", ["BIO_BACTERIA", "BIO_VIRUSES", "BIO_DISEASES",
                                               "BIO_DIS_BACTERIAL", "BIO_IMMUNE",
                                               "BIO_VECTOR", "BIO_PROTOZOA", "BIO_FUNGI"]),
            ("Ecology & Environment",         ["BIO_ECOLOGY", "BIO_BIOMES", "BIO_FOOD_CHAINS",
                                               "BIO_ECOSYSTEMS"]),
            ("Classification & Nutrition",    ["BIO_ANIMAL", "BIO_VITAMINS",
                                               "BIO_HUMAN_BODY", "BIO_HUMAN_SYSTEMS",
                                               "BIO_MIXED"]),
        ],
    },
    {
        "id": "physics",
        "name": "Physics",
        "icon": "atom",
        "color": "#7B2FBE",
        "sources": ["Physics"],
        "chapters": [
            ("Mechanics & Motion",            ["PHY_MOTION", "PHY_FORCES", "PHY_FRICTION",
                                               "PHY_KINEMATICS", "PHY_NEWTON", "PHY_VECTORS",
                                               "PHY_PROJECTILE", "PHY_MOMENTUM",
                                               "PHY_WORK_ENERGY", "PHY_SIMPLE_MACHINES",
                                               "PHY_SHM", "PHY_LAWS"]),
            ("Gravitation & Fluids",          ["PHY_GRAVITATION", "PHY_BUOYANCY",
                                               "PHY_FLUIDS", "PHY_PRESSURE"]),
            ("Heat & Thermodynamics",         ["PHY_HEAT", "PHY_THERMODYNAMICS"]),
            ("Light & Optics",                ["PHY_LIGHT", "PHY_OPTICS"]),
            ("Sound & Waves",                 ["PHY_SOUND", "PHY_WAVES"]),
            ("Electricity & Magnetism",       ["PHY_CURRENT", "PHY_ELECTRICITY",
                                               "PHY_ELECTRIC", "PHY_ELECTRO",
                                               "PHY_MAGNETISM", "PHY_MAGNETIC"]),
            ("Modern Physics",                ["PHY_MODERN", "PHY_NUCLEAR",
                                               "PHY_RADIOACTIVITY", "PHY_LASER",
                                               "PHY_SEMICONDUCTORS", "PHY_EM_SPECTRUM"]),
            ("Units & Measurements",          ["PHY_UNITS"]),
        ],
    },
    {
        "id": "chemistry",
        "name": "Chemistry",
        "icon": "flask.fill",
        "color": "#006D77",
        "sources": ["Chemistry"],
        "chapters": [
            ("Atomic Structure & Periodic Table", ["CHEM_ATOMIC", "CHEM_PERIODIC",
                                                   "CHE_ATOMIC", "CHE_PERIODIC",
                                                   "CHEM_OXIDATION"]),
            ("Chemical Bonding & Reactions",  ["CHEM_CHEMICAL", "CHEM_RATE",
                                               "CHEM_EQUILIBRIUM", "CHEM_CATALYSIS",
                                               "CHE_REACTIONS", "CHEM_THERMODYNAMICS"]),
            ("Acids, Bases & Solutions",      ["CHEM_ACIDS", "CHEM_PH", "CHEM_SOLUTIONS",
                                               "CHE_ACIDS", "CHEM_COLLOIDS", "CHEM_WATER",
                                               "CHEM_SEPARATION"]),
            ("Gases & Electrochemistry",      ["CHEM_GASES", "CHE_GASES",
                                               "CHEM_ELECTROCHEMISTRY", "CHEM_REDOX",
                                               "CHEM_OXIDES"]),
            ("Metals, Non-metals & Blocks",   ["CHEM_ALKALI", "CHEM_HALOGENS",
                                               "CHEM_NITROGEN", "CHEM_NOBLE_GASES",
                                               "CHEM_OXYGEN", "CHEM_HYDROGEN",
                                               "CHEM_METALLURGY", "CHE_METALS",
                                               "CHE_NONMETALS", "CHEM_S_BLOCK",
                                               "CHEM_p_BLOCK", "CHEM_d_BLOCK"]),
            ("Organic Chemistry",             ["CHEM_ORGANIC", "CHEM_HYDROCARBONS",
                                               "CHEM_FUNCTIONAL", "CHEM_ALCOHOLS",
                                               "CHE_ORGANIC", "CHE_CARBON"]),
            ("Applied Chemistry",             ["CHEM_BIOMOLECULES", "CHEM_PLASTICS",
                                               "CHEM_SOAPS", "CHEM_EVERYDAY",
                                               "CHE_EVERYDAY", "CHEM_ATMOSPHERIC",
                                               "CHEM_NUCLEAR_CHEMISTRY"]),
            ("Elements & Mixed",              ["CHE_ELEMENTS", "CHE_MIXED"]),
        ],
    },
    {
        "id": "environment",
        "name": "Environment & Ecology",
        "icon": "globe.europe.africa.fill",
        "color": "#40916C",
        "sources": ["Environment"],
        "chapters": [
            ("Climate Change & Agreements",   ["ENV_CLIMATE", "ENV_PARIS",
                                               "ENV_CLIMATE_SUMMITS", "ENV_CLIMATE_INDICATORS",
                                               "ENV_CONVENTIONS", "ENV_OZONE"]),
            ("Biodiversity & Conservation",   ["ENV_BIODIVERSITY", "ENV_WILDLIFE",
                                               "ENV_NATIONAL_PARKS", "ENV_PROTECTED_AREAS",
                                               "ENV_BIOSPHERE", "ENV_FORESTS",
                                               "ENV_FOREST_CONSERVATION", "ENV_RAMSAR",
                                               "ENV_WETLANDS", "ENV_INVASIVE"]),
            ("Pollution & Land",              ["ENV_AIR_QUALITY", "ENV_POLLUTION",
                                               "ENV_WATER_POLLUTION", "ENV_LAND_DEGRADATION",
                                               "ENV_ECOLOGY"]),
            ("Renewable Energy & Disasters",  ["ENV_SUSTAINABLE", "ENV_RENEWABLE",
                                               "ENV_GREEN", "ENV_DISASTERS",
                                               "ENV_NUCLEAR_WASTE"]),
            ("Laws & Organizations",          ["ENV_ENVIRONMENTAL_LAWS", "ENV_NGT",
                                               "ENV_ORGS", "ENV_GLACIERS"]),
        ],
    },
    {
        "id": "general_knowledge",
        "name": "General Knowledge",
        "icon": "star.fill",
        "color": "#E5A020",
        "sources": ["General Knowledge", "General Awareness"],
        "chapters": [
            ("Awards & Honours",              ["GK_AWARDS", "GK_BHARAT_RATNA", "GK_NOBEL"]),
            ("Sports & Olympics",             ["GK_SPORTS", "GK_OLYMPICS",
                                               "GK_FIRSTS_INDIA", "GK_FIRST_WOMEN"]),
            ("Art, Culture & Heritage",       ["GK_CLASSICAL_DANCES", "GK_FOLK_DANCES",
                                               "GK_PAINTINGS", "GK_MUSICAL", "GK_MUSIC",
                                               "GK_TEMPLES", "GK_FESTIVALS", "GK_UNESCO",
                                               "GK_GI_TAGS", "GK_BOOKS_AUTHORS",
                                               "GK_LITERATURE", "GK_CINEMA",
                                               "GK_FAMOUS_QUOTES", "GK_INDIAN_FILMS",
                                               "GK_INDIAN_CLASSICAL", "GK_INDIAN_FAIRS",
                                               "GK_INDIAN_HANDICRAFTS", "GK_INDIAN_NEWSPAPERS"]),
            ("India — States & Symbols",      ["GK_INDIAN_STATES", "GK_STATES_CAPITALS",
                                               "GK_NATIONAL_SYMBOLS", "GK_NAT_SYMBOLS",
                                               "GK_NATIONAL_PARKS", "GK_NICKNAMES",
                                               "GK_FIRSTS", "GK_SUPERLATIVES",
                                               "GK_FAMOUS_BATTLES", "GK_TRIBES",
                                               "GK_INDIAN_TRIBES"]),
            ("India — Infrastructure",        ["GK_AIRPORTS_PORTS", "GK_RIVERS",
                                               "GK_DAMS_RIVERS", "GK_SCHEMES",
                                               "GK_RIVERS_DAMS"]),
            ("International & Organizations", ["GK_COUNTRIES", "GK_CURRENCIES",
                                               "GK_CAPITALS_CURRENCIES", "GK_INTL_ORG",
                                               "GK_INTL_ORGS", "GK_INTL_SUMMITS",
                                               "GK_SEVEN_WONDERS", "GK_UN_AGENCIES",
                                               "GK_ANIMALS_WILDLIFE"]),
            ("Science, Tech & Defence",       ["GK_SCIENCE", "GK_INVENTIONS",
                                               "GK_COMPUTER", "GK_DEFENCE", "GK_ISRO",
                                               "GK_POLITY_CURRENT", "GK_GOVT_DOCUMENTS",
                                               "GK_PMS_PRESIDENTS", "GK_ENV_CLIMATE",
                                               "GA_CURRENT"]),
        ],
    },
    {
        "id": "quantitative_aptitude",
        "name": "Quantitative Aptitude",
        "icon": "function",
        "color": "#5A4AE3",
        "sources": ["Quantitative Aptitude", "Quant"],
        "chapters": [
            ("Number System",                 ["QNT_NUMBER", "QNT_LCM_HCF", "QNT_HCF_LCM",
                                               "QNT_SIMPLIFICATION", "QNT_SURDS",
                                               "QNT_LOGARITHMS"]),
            ("Percentages & Profit-Loss",     ["QNT_PERCENTAGE", "QNT_PROFIT_LOSS",
                                               "QNT_PROFIT", "QNT_MIXTURE",
                                               "QNT_ALLIGATION", "QNT_MIXTURE_ALLIGATION"]),
            ("Ratios & Averages",             ["QNT_RATIO", "QNT_AVERAGES", "QNT_AVERAGE",
                                               "QNT_AVG_RATIO", "QNT_AGES",
                                               "QNT_PARTNERSHIP"]),
            ("Time, Speed & Distance",        ["QNT_SPEED", "QNT_TIME_DISTANCE",
                                               "QNT_TIME_SPEED", "QNT_TRAINS",
                                               "QNT_BOATS", "QNT_BOAT_STREAM",
                                               "QNT_TSD"]),
            ("Time & Work",                   ["QNT_TIME_WORK", "QNT_PIPES"]),
            ("Simple & Compound Interest",    ["QNT_SIMPLE_INTEREST", "QNT_COMPOUND",
                                               "QNT_SI_CI"]),
            ("Mensuration & Geometry",        ["QNT_MENSURATION", "QNT_GEOMETRY",
                                               "QNT_TRIGONOMETRY"]),
            ("Algebra, Probability & Stats",  ["QNT_ALGEBRA", "QNT_QUADRATIC",
                                               "QNT_PERMUTATION", "QNT_PROBABILITY",
                                               "QNT_STATISTICS", "QNT_INEQUALITIES",
                                               "QNT_PROGRESSION"]),
            ("Data Interpretation",           ["QNT_DATA", "QNT_DI",
                                               "QNT_NUMBER_SERIES"]),
        ],
    },
    {
        "id": "logical_reasoning",
        "name": "Logical Reasoning",
        "icon": "brain.head.profile",
        "color": "#D63031",
        "sources": ["Reasoning"],
        "chapters": [
            ("Series & Sequences",            ["REAS_SERIES", "REAS_LETTER_SERIES",
                                               "REAS_NUMBER_SERIES", "REAS_ALPHANUMERIC"]),
            ("Analogy & Classification",      ["REAS_ANALOGY", "REAS_CLASSIFICATION",
                                               "REAS_ODD_ONE_OUT"]),
            ("Coding & Decoding",             ["REAS_CODING"]),
            ("Direction & Ranking",           ["REAS_DIRECTION", "REAS_ORDER_RANKING"]),
            ("Blood Relations",               ["REAS_BLOOD_RELATION"]),
            ("Seating & Puzzles",             ["REAS_SEATING", "REAS_PUZZLE",
                                               "REAS_DATA_ARRANGEMENT"]),
            ("Syllogism & Venn Diagrams",     ["REAS_SYLLOGISM", "REAS_VENN",
                                               "REAS_LOGICAL_DEDUCTION",
                                               "REAS_STATEMENT", "REAS_CAUSE_EFFECT",
                                               "REAS_DECISION"]),
            ("Clocks, Calendars & Dice",      ["REAS_CALENDAR", "REAS_CLOCK", "REAS_DICE"]),
            ("Miscellaneous",                 ["REAS_INPUT_OUTPUT", "REAS_DATA_SUFFICIENCY",
                                               "REAS_NONVERBAL", "REAS_NON_VERBAL",
                                               "REAS_SYMBOL", "REAS_MATHEMATICAL",
                                               "REAS_INEQUALITIES", "REAS_NUMBER_PUZZLE"]),
        ],
    },
    {
        "id": "english_language",
        "name": "English Language",
        "icon": "text.quote",
        "color": "#C0392B",
        "sources": ["English", "Vocabulary"],
        "chapters": [
            ("Grammar — Parts of Speech",    ["ENG_ARTICLES", "ENG_PREPOSITIONS",
                                               "ENG_CONJUNCTIONS", "ENG_NOUN",
                                               "ENG_PRONOUNS", "ENG_ADVERBS",
                                               "ENG_SV_AGREEMENT"]),
            ("Verb Forms & Tenses",           ["ENG_TENSES", "ENG_VOICE",
                                               "ENG_ACTIVE_PASSIVE", "ENG_PASSIVE_VOICE",
                                               "ENG_NARRATION", "ENG_DIRECT_INDIRECT",
                                               "ENG_REPORTED_SPEECH", "ENG_GERUND",
                                               "ENG_MODAL", "ENG_PARTICIPLES",
                                               "ENG_CONDITIONALS", "ENG_TRANSFORMATION"]),
            ("Sentence & Error Correction",  ["ENG_SENTENCE_IMPROVEMENT",
                                               "ENG_PARA_JUMBLE", "ENG_FILL_BLANKS",
                                               "ENG_CLOZE", "ENG_ERROR_SPOTTING",
                                               "ENG_QUESTION_TAG", "ENG_PUNCTUATION",
                                               "ENG_DEGREES", "ENG_SPELLING"]),
            ("Reading Comprehension",        ["ENG_READING", "ENG_RC_PASSAGE",
                                               "ENG_PASSAGE_COMPRE"]),
            ("Idioms & Phrasal Verbs",       ["ENG_IDIOMS", "ENG_PHRASAL_VERBS",
                                               "ENG_ONE_WORD", "VOCAB_IDIOMS",
                                               "VOCAB_PHRASAL"]),
            ("Synonyms & Antonyms",          ["ENG_SYNONYM", "ENG_SYNONYMS",
                                               "VOCAB_SYNONYMS", "VOCAB_ANTONYMS",
                                               "VOCAB_HIGH_HIT", "VOCAB_MIXED",
                                               "VOCAB_OPPOSITES"]),
            ("Word Roots & Word Formation",  ["VOCAB_PREFIXES", "VOCAB_SUFFIXES",
                                               "VOCAB_ROOTS", "VOCAB_CIDES",
                                               "VOCAB_CRACIES", "VOCAB_OLOGIES",
                                               "VOCAB_MANIAS", "VOCAB_PHOBIAS",
                                               "VOCAB_GRECO"]),
            ("Confusables & Word Usage",     ["VOCAB_CONFUSABLES", "VOCAB_CONFUSED",
                                               "VOCAB_FOREIGN", "VOCAB_HOMOPHONES",
                                               "VOCAB_HOMOGRAPHS", "VOCAB_CONTEXT",
                                               "VOCAB_ONE_WORD", "VOCAB_OWS"]),
            ("Domain Vocabulary",            ["VOCAB_BUSINESS", "VOCAB_LAW_LEGAL",
                                               "VOCAB_MEDICAL", "VOCAB_SCIENTIFIC",
                                               "VOCAB_GOVERNMENT", "VOCAB_LITERATURE",
                                               "VOCAB_TRAVEL", "VOCAB_PERSONALITY",
                                               "VOCAB_EMOTIONS", "VOCAB_PROVERBS"]),
        ],
    },
]

# ─── Question type classification ────────────────────────────────────────────

def classify(subject: str, topic_code: str, stem: str) -> tuple[str, int]:
    """Returns (questionType, timeLimitSeconds)."""
    tc  = topic_code.upper()
    s   = stem.lower()

    # Arithmetic — needs actual calculation
    if tc.startswith("QNT_"):
        arithmetic_topics = ["PERCENTAGE", "PROFIT", "RATIO", "INTEREST", "TIME_WORK",
                              "SPEED", "AGES", "AVERAGE", "MENSURATION", "MIXTURE",
                              "PERMUTATION", "PROBABILITY", "BOATS", "TRAINS",
                              "PIPES", "DATA_INTERPRETATION", "DI_", "PROGRESSION"]
        for t in arithmetic_topics:
            if t in tc:
                return "arithmetic", 50
        return "arithmetic", 40   # all quant is some form of arithmetic

    # Reasoning
    if tc.startswith("REAS_"):
        return "reasoning", 38

    # Verbal / English
    if tc.startswith(("ENG_", "VOCAB_")):
        return "verbal", 25

    # Science subjects
    if tc.startswith(("BIO_", "PHY_", "CHEM_", "CHE_", "ENV_")):
        return "science", 28

    # Legal / Polity / Constitutional
    if tc.startswith("POL_"):
        return "legal", 25

    # History, Geography, Economy, GK — factual
    return "factual", 28

# ─── Helpers ─────────────────────────────────────────────────────────────────

def stable_uuid(seed: str) -> str:
    """Deterministic UUID from a seed string (no randomness, idempotent re-runs)."""
    h = hashlib.md5(seed.encode()).hexdigest()
    return str(uuid.UUID(h))

OPTION_LETTERS = "ABCD"

def build_card_dto(q: dict, chapter: str, chapter_name: str,
                   subj_id: str) -> dict:
    """Convert a static_gk question dict → BackupFile CardDTO dict."""
    stem   = q["stem"].strip()
    opts   = q.get("options", [])
    expln  = (q.get("explanation") or "").strip()
    tc     = q.get("topic_code", "")
    topic  = q.get("topic", "")
    diff   = str(q.get("difficulty", "")).upper()
    cl     = (q.get("correct_letter") or "A").upper()

    # Map correct letter → option index
    ci = ord(cl) - ord("A") if cl in OPTION_LETTERS else 0
    ci = max(0, min(ci, len(opts) - 1))

    correct_text = opts[ci]["option_text"].strip() if opts else ""
    wrong_opts   = [o["option_text"].strip() for i, o in enumerate(opts) if i != ci]

    # Build front: stem + MCQ options
    opt_lines = "\n".join(
        f"({OPTION_LETTERS[i]}) {o['option_text'].strip()}"
        for i, o in enumerate(opts)
    )
    front = f"{stem}\n\n{opt_lines}" if opt_lines else stem

    # Build back: answer + classification prefix + explanation
    classification_prefix = f"{chapter} — " if chapter else ""
    back = f"({cl}) {correct_text}\n\n{classification_prefix}{expln}" if expln else f"({cl}) {correct_text}"

    q_type, time_limit = classify(q.get("subject", ""), tc, stem)

    # Deterministic ID from subject_id + question id
    card_id = stable_uuid(f"{subj_id}_{q.get('id', stem[:40])}")

    return {
        "id": card_id,
        "front": front,
        "back": back,
        "box": 1,
        "nextReview": NOW_ISO,
        "lastReviewed": None,
        "createdAt": NOW_ISO,
        "correctCount": 0,
        "wrongCount": 0,
        "ease": 2.5,
        "interval": 0,
        "repetitions": 0,
        "frontImageBase64": None,
        "backImageBase64": None,
        "option1": wrong_opts[0] if len(wrong_opts) > 0 else None,
        "option2": wrong_opts[1] if len(wrong_opts) > 1 else None,
        "option3": wrong_opts[2] if len(wrong_opts) > 2 else None,
        "storedExplanation": expln or None,
        "userDifficulty": 0,
        "fsrsStability": None,
        "fsrsDifficulty": None,
        "ratingHistory": None,
        "chapter": chapter,
        "chapterName": chapter_name,
        "questionType": q_type,
        "timeLimitSeconds": time_limit,
    }

def chapter_for_topic_code(tc: str, chapter_map: list) -> tuple[str, str]:
    """Return (chapter_code, chapter_name) for a topic_code using prefix matching."""
    tc_upper = tc.upper()
    for ch_name, prefixes in chapter_map:
        for prefix in prefixes:
            if tc_upper.startswith(prefix.upper()):
                return ch_name, ch_name
    return "Miscellaneous", "Miscellaneous"

# ─── Load static_gk files ────────────────────────────────────────────────────

def load_all_questions():
    """Returns dict: subject_display_name -> list of question dicts (with topic_code)."""
    all_q = defaultdict(list)
    seen_ids = set()

    for jsonfile in sorted(glob.glob(os.path.join(STATIC_GK_DIR, "**", "*.json"), recursive=True)):
        try:
            with open(jsonfile, encoding="utf-8") as f:
                d = json.load(f)
        except Exception:
            continue

        if "questions" not in d:
            continue

        subj = d.get("subject", "Unknown")
        tc   = d.get("topic_code", "")

        # Normalise subject names
        if subj in ("Quant",):
            subj = "Quantitative Aptitude"
        if subj in ("General Awareness",):
            subj = "General Knowledge"

        for q in d["questions"]:
            # Carry file-level metadata down to each question
            q.setdefault("subject", subj)
            q.setdefault("topic_code", tc)
            q.setdefault("topic", d.get("topic", ""))

            # Dedup by question id
            qid = q.get("id", "")
            if qid and qid in seen_ids:
                continue
            if qid:
                seen_ids.add(qid)

            all_q[subj].append(q)

    return all_q

# ─── Build BackupFile-format subject JSON ────────────────────────────────────

def build_subject_backup(subject_def: dict, all_q: dict) -> dict:
    """Build a BackupFile dict for one subject, one deck per chapter."""
    subject_sources = subject_def["sources"]
    chapter_map     = subject_def["chapters"]
    subj_id         = subject_def["id"]
    color           = subject_def["color"]

    # Collect all questions for this subject's sources
    questions = []
    for src in subject_sources:
        questions.extend(all_q.get(src, []))

    # Assign each question to a chapter
    chapter_cards: dict[str, list] = defaultdict(list)
    chapter_order: dict[str, int] = {}
    for idx, (ch_name, _) in enumerate(chapter_map):
        chapter_order[ch_name] = idx

    for q in questions:
        tc = q.get("topic_code", "")
        ch_name, _ = chapter_for_topic_code(tc, chapter_map)
        card = build_card_dto(q, ch_name, ch_name, subj_id)
        chapter_cards[ch_name].append(card)

    # One deck per chapter
    decks = []
    for idx, (ch_name, _) in enumerate(chapter_map):
        cards = chapter_cards.get(ch_name, [])
        if not cards:
            continue
        deck_id = stable_uuid(f"{subj_id}_deck_{ch_name}")
        decks.append({
            "id": deck_id,
            "name": ch_name,
            "colorHex": color,
            "createdAt": NOW_ISO,
            "cards": cards,
            "isPinned": False,
            "sortOrder": idx,
            "isDeleted": False,
            "deletedAt": None,
        })

    return {
        "version": 2,
        "exportedAt": NOW_ISO,
        "decks": decks,
        "tags": [],
    }

# ─── EPFO enrichment ─────────────────────────────────────────────────────────

# Chapter code regex: matches e.g. "II.4 Applicability", "II.A Short Title"
CHAPTER_PATTERN = re.compile(
    r'\b([IVXLC]+\.[0-9A-Za-z]+)\s+'   # code: II.4
    r'([A-Za-z7&][A-Za-z0-9 &/()\'-]*?)'  # name
    r'(?:\s*[—\-–]|\s*S\.\d|\Z)',
    re.MULTILINE
)

EPFO_CHAPTER_NAMES = {
    # EPF Act 1952
    "II.A": "Short Title & Extent", "II.4": "Applicability",
    "II.5": "Contributions",        "II.6": "CBT Structure",
    "II.7": "Offences & Penalties", "II.8": "7A Enquiry",
    "II.9": "Inspector Powers",
    # EPS 1995
    "III.11": "EPS Applicability",  "III.12": "Pension Formula",
    "III.13": "Types of Pension",   "III.14": "Higher Pension",
    "III.15": "Funds & CPPS",       "III.16": "Nomination",
    "III.17": "Pension Disbursement",
    # EDLI
    "IV.18": "EDLI Basics",         "IV.19": "Benefit Formula",
    "IV.20": "Exemption",           "IV.21": "Claim Process",
    # SS Code
    "V.23": "SS Code Overview",     "V.24": "Scope & Coverage",
    "V.25": "Benefits",             "V.26": "ESIC under Code",
    "V.27": "Compliance",
    # Labour Laws
    "VI.28": "ID Act 1947",         "VI.29": "Minimum Wages Act",
    "VI.30": "Gratuity Act",        "VI.31": "Bonus Act",
    "VI.32": "Maternity Benefit",
    # Economy
    "VII.33": "Macro Basics",       "VII.34": "Banking & RBI",
    "VII.35": "Budget",             "VII.36": "Inflation",
    # Polity
    "VIII.37": "Constitution",      "VIII.38": "DPSPs",
    "VIII.39": "Parliamentary Sys", "VIII.40": "Schedules",
    # Accounting
    "IX.41": "Fundamentals",        "IX.42": "Financial Statements",
    "IX.43": "Ratios",
    # History
    "X.44": "Freedom Struggle",     "X.45": "Labour Movement",
    # Science
    "XI.46": "Physics",
    # Current Affairs
    "XII.47": "EPFO Updates",       "XII.48": "Judgments",
    # Revision
    "XIII.49": "Mixed Revision",    "XIII.50": "High Difficulty",
    "XIII.51": "Judgment Spot",     "XIII.52": "Mock Sampler",
    "XIII.53": "Final Mock",
    # Geography
    "XV.59": "Physical Geography",  "XV.60": "Economic Geography",
    # Gap Patches
    "XVI.61": "Insurance",          "XVI.62": "Tribal Rebellions",
    "XVI.63": "Art & Culture",
}

def epfo_question_type(deck_name: str, back: str) -> tuple[str, int]:
    if "Accounting" in deck_name:
        return "accounting", 32
    if any(x in deck_name for x in ["EPF", "EPS", "EDLI", "Labour", "SS Code"]):
        return "legal", 25
    if "Science" in deck_name:
        return "science", 28
    # Economy, Polity, History, Current Affairs, Geography
    return "factual", 28

def enrich_epfo():
    with open(EPFO_JSON, encoding="utf-8") as f:
        data = json.load(f)

    for deck in data.get("decks", []):
        for card in deck.get("cards", []):
            back = card.get("back", "")
            m = CHAPTER_PATTERN.search(back)
            code      = m.group(1).strip() if m else ""
            ch_name   = EPFO_CHAPTER_NAMES.get(code, m.group(2).strip() if m else "") if m else ""
            q_type, tlimit = epfo_question_type(deck.get("name", ""), back)
            card["chapter"]          = code
            card["chapterName"]      = ch_name
            card["questionType"]     = q_type
            card["timeLimitSeconds"] = tlimit

    out_path = EPFO_JSON.replace(".json", "_v2.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"  Wrote enriched EPFO: {out_path}")
    return out_path

# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    print("Loading all static_gk questions…")
    all_q = load_all_questions()
    total = sum(len(v) for v in all_q.values())
    print(f"  Loaded {total} questions across {len(all_q)} subjects")

    manifest = []

    for subj_def in SUBJECTS:
        name = subj_def["name"]
        print(f"Building: {name}…")
        backup = build_subject_backup(subj_def, all_q)

        card_count    = sum(len(d["cards"]) for d in backup["decks"])
        chapter_count = len(backup["decks"])

        filename = f"library_{subj_def['id']}.json"
        out_path = os.path.join(OUT_DIR, filename)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(backup, f, ensure_ascii=False, indent=2)
        print(f"  → {filename}: {chapter_count} chapters, {card_count} cards")

        manifest.append({
            "id":          subj_def["id"],
            "name":        name,
            "icon":        subj_def["icon"],
            "colorHex":    subj_def["color"],
            "cardCount":   card_count,
            "filename":    filename,
            "chapters": [
                {
                    "name":      d["name"],
                    "cardCount": len(d["cards"]),
                    "deckId":    d["id"],
                }
                for d in backup["decks"]
            ],
        })

    # Write manifest
    manifest_path = os.path.join(OUT_DIR, "library_manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print(f"\nManifest written: {manifest_path}")

    print("\nEnriching EPFO JSON…")
    enrich_epfo()

    print("\nDone ✓")

if __name__ == "__main__":
    main()
