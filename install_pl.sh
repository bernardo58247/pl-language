#!/usr/bin/env bash

set -e

echo "=== instalando PL no Linux / installing PL on Linux ==="

# 1. verifica permissões de superusuário
if [ "$EUID" -ne 0 ]; then
    echo "erro: execute o script usando sudo / error: run using sudo"
    exit 1
fi

# 2. detecta gerenciador de pacotes e instala o g++
if command -v apt &> /dev/null; then
    apt update && apt install -y g++ mpv
elif command -v dnf &> /dev/null; then
    dnf install -y gcc-c++ mpv
elif command -v pacman &> /dev/null; then
    pacman -Sy --noconfirm gcc mpv
fi

# 3. cria o código C++ adaptado para o Linux
cat << 'EOF' > pl_linux.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <map>
#include <regex>
#include <cstdlib>
#include <sstream>

using namespace std;

map<string, string> escopo_global;
string lang_system = "en";

void detectar_idioma() {
    const char* env_lang = getenv("LANG");
    if (!env_lang) env_lang = getenv("LC_ALL");
    string l = env_lang ? string(env_lang) : "";
    
    if (l.rfind("pt", 0) == 0) lang_system = "pt";
    else if (l.rfind("es", 0) == 0) lang_system = "es";
    else lang_system = "en";
}

string t(const string& key) {
    static map<string, map<string, string>> msgs = {
        {"err_lang", {
            {"pt", "a linguagem não é suportada por padrão."},
            {"en", "language is not supported by default."},
            {"es", "el lenguaje no está soportado por defecto."}
        }},
        {"err_som", {
            {"pt", "erro: o arquivo de som não foi encontrado: "},
            {"en", "error: sound file was not found: "},
            {"es", "error: no se encontró el archivo de sonido: "}
        }},
        {"choose_opt", {
            {"pt", "escolha uma opção: "},
            {"en", "choose an option: "},
            {"es", "elija una opción: "}
        }},
        {"err_file", {
            {"pt", "erro: arquivo não encontrado: "},
            {"en", "error: file not found: "},
            {"es", "error: archivo no encontrado: "}
        }},
        {"banner", {
            {"pt", "--- PL (Portuguese Language) Nativa [Linux] ---\ndigite 'sair' para encerrar.\n"},
            {"en", "--- PL (Portuguese Language) Native [Linux] ---\ntype 'sair' or 'exit' to quit.\n"},
            {"es", "--- PL (Portuguese Language) Nativa [Linux] ---\nescriba 'sair' o 'salir' para terminar.\n"}
        }}
    };
    if (msgs.count(key) && msgs[key].count(lang_system)) {
        return msgs[key][lang_system];
    }
    return msgs[key]["en"];
}

string trim(const string& str) {
    size_t first = str.find_first_not_of(" \t\n\r");
    if (string::npos == first) return "";
    size_t last = str.find_last_not_of(" \t\n\r");
    return str.substr(first, (last - first + 1));
}

string remover_aspas(const string& str) {
    string s = trim(str);
    if (s.length() >= 2 && s.front() == '"' && s.back() == '"') {
        return s.substr(1, s.length() - 2);
    }
    return s;
}

string buscar_variavel(const string& nome, map<string, string>& escopo_local) {
    string var = trim(nome);
    if (escopo_local.count(var)) return escopo_local[var];
    if (escopo_global.count(var)) return escopo_global[var];
    return remover_aspas(var);
}

string formatar_texto(string texto, map<string, string>& escopo_local) {
    for (auto const& [var, val] : escopo_local) {
        string alvo = "$" + var;
        size_t pos = 0;
        while ((pos = texto.find(alvo, pos)) != string::npos) {
            texto.replace(pos, alvo.length(), val);
            pos += val.length();
        }
    }
    for (auto const& [var, val] : escopo_global) {
        string alvo = "$" + var;
        size_t pos = 0;
        while ((pos = texto.find(alvo, pos)) != string::npos) {
            texto.replace(pos, alvo.length(), val);
            pos += val.length();
        }
    }
    return texto;
}

void executar_linguagem_externa(const string& lang, const string& codigo) {
    string ext, exec;
    if (lang == "python") { exec = "python3"; ext = ".py"; }
    else if (lang == "node" || lang == "javascript" || lang == "node.js") { exec = "node"; ext = ".js"; }
    else if (lang == "bash") { exec = "bash"; ext = ".sh"; }
    else if (lang == "ruby") { exec = "ruby"; ext = ".rb"; }
    else if (lang == "php") { exec = "php"; ext = ".php"; }
    else {
        cout << lang << ": " << t("err_lang") << "\n";
        return;
    }

    string temp_file = "/tmp/pl_script" + ext;
    ofstream out(temp_file);
    out << codigo;
    out.close();

    string cmd = exec + " " + temp_file;
    system(cmd.c_str());
    remove(temp_file.c_str());
}

void executar(string codigo, map<string, string>& escopo_local) {
    stringstream ss(codigo);
    string linha;
    vector<string> linhas;

    while (getline(ss, linha)) {
        string l = trim(linha);
        if (!l.empty() && l.rfind("//", 0) != 0) {
            linhas.push_back(l);
        }
    }

    for (size_t i = 0; i < linhas.size(); ++i) {
        string l = linhas[i];

        if (l.rfind("se", 0) == 0) {
            regex reg_se("se\\s*\\[\\s*(.*?)\\s*\\]\\s*então\\s*\\((.*?)(?:\\s+senão\\s+(.*?))?\\)");
            smatch match;
            if (regex_search(l, match, reg_se)) {
                string cond = match[1].str();
                string bloco_entao = match[2].str();
                string bloco_senao = match[3].str();

                size_t pos_eq = cond.find('=');
                bool resultado = false;
                if (pos_eq != string::npos) {
                    string esq = buscar_variavel(cond.substr(0, pos_eq), escopo_local);
                    string dir = buscar_variavel(cond.substr(pos_eq + 1), escopo_local);
                    resultado = (esq == dir);
                }

                string bloco_exec = resultado ? bloco_entao : bloco_senao;
                if (!bloco_exec.empty()) {
                    stringstream ss_b(bloco_exec);
                    string sub_cmd;
                    while (getline(ss_b, sub_cmd, ';')) {
                        if (!trim(sub_cmd).empty()) executar(trim(sub_cmd), escopo_local);
                    }
                }
            }
        }
        else if (l.rfind("tocar_som", 0) == 0) {
            regex reg_som("tocar_som\\s*\"(.*?)\"(?:\\s+no\\s+volume\\s+(\\d+|\\w+))?");
            smatch match;
            if (regex_search(l, match, reg_som)) {
                string caminho = formatar_texto(match[1].str(), escopo_local);
                string vol = match[2].matched ? match[2].str() : "";

                ifstream f(caminho.c_str());
                if (!f.good()) {
                    cout << t("err_som") << "'" << caminho << "'\n";
                } else {
                    string cmd_play;
                    if (!vol.empty()) {
                        string val_vol = buscar_variavel(vol, escopo_local);
                        cmd_play = "mpv --no-terminal --volume=" + val_vol + " \"" + caminho + "\" &";
                    } else {
                        cmd_play = "mpv --no-terminal \"" + caminho + "\" &";
                    }
                    system(cmd_play.c_str());
                }
            }
        }
        else if (l.rfind("interagir_com", 0) == 0) {
            regex reg_lang("interagir_com\\s*\"(.*?)\"\\s*\\((.*?)\\)");
            smatch match;
            if (regex_search(l, match, reg_lang)) {
                executar_linguagem_externa(match[1].str(), match[2].str());
            }
        }
        else if (l.rfind("escolhas", 0) == 0) {
            regex reg_esc("escolhas\\s*\"(.*?)\"\\s*\\((.*?)\\)");
            smatch match;
            if (regex_search(l, match, reg_esc)) {
                cout << match[1].str() << "\n";
                stringstream ss_op(match[2].str());
                string op_linha;
                map<string, string> opcoes;

                while (getline(ss_op, op_linha)) {
                    size_t pos = op_linha.find('=');
                    if (pos != string::npos) {
                        string k = trim(op_linha.substr(0, pos));
                        string v = remover_aspas(op_linha.substr(pos + 1));
                        opcoes[k] = v;
                        cout << "[" << k << "] " << v << "\n";
                    }
                }

                cout << t("choose_opt");
                string resp;
                cin >> resp;
                cin.ignore();
                escopo_local["opcao_escolhida"] = opcoes.count(resp) ? opcoes[resp] : "";
            }
        }
        else if (l.rfind("ler.input", 0) == 0) {
            regex reg_in("ler\\.input\\s*\"(.*?)\"(?:\\s+para\\s+(\\w+))?");
            smatch match;
            if (regex_search(l, match, reg_in)) {
                cout << match[1].str();
                string ent;
                getline(cin, ent);
                if (match[2].matched) {
                    escopo_local[match[2].str()] = trim(ent);
                }
            }
        }
        else if (l.rfind("executar.os", 0) == 0) {
            regex reg_os("executar\\.os\\s*\"(.*?)\"");
            smatch match;
            if (regex_search(l, match, reg_os)) {
                string cmd = formatar_texto(match[1].str(), escopo_local);
                system(cmd.c_str());
            }
        }
        else if (l.rfind("repetir", 0) == 0) {
            regex reg_rep("repetir\\s*\\((.*?)\\)\\s*\\((\\d+|\\w+)\\)");
            smatch match;
            if (regex_search(l, match, reg_rep)) {
                string bloco = match[1].str();
                int vezes = stoi(buscar_variavel(match[2].str(), escopo_local));
                for (int r = 0; r < vezes; ++r) {
                    stringstream ss_r(bloco);
                    string sub_cmd;
                    while (getline(ss_r, sub_cmd, ';')) {
                        if (!trim(sub_cmd).empty()) executar(trim(sub_cmd), escopo_local);
                    }
                }
            }
        }
        else if (l.find("definir") != string::npos) {
            regex reg_loc("definir\\s+(\\w+)\\s+como\\s+variável\\s+local\\s*=\\s*(.+)");
            regex reg_glob("definir\\s+(\\w+)\\s+como\\s+variável\\s*=\\s*(.+)");
            smatch match;

            if (regex_search(l, match, reg_loc)) {
                escopo_local[match[1].str()] = remover_aspas(match[2].str());
            } else if (regex_search(l, match, reg_glob)) {
                escopo_global[match[1].str()] = remover_aspas(match[2].str());
            }
        }
        else if (l.rfind("mostrar", 0) == 0) {
            string alvo = trim(l.substr(7));
            cout << buscar_variavel(alvo, escopo_local) << "\n";
        }
    }
}

int main(int argc, char* argv[]) {
    detectar_idioma();
    map<string, string> escopo_local;

    if (argc > 1) {
        ifstream file(argv[1]);
        if (!file.is_open()) {
            cout << t("err_file") << "'" << argv[1] << "'\n";
            return 1;
        }
        stringstream buffer;
        buffer << file.rdbuf();
        executar(buffer.str(), escopo_local);
    } else {
        cout << t("banner");
        string entrada;
        while (true) {
            cout << "PL> ";
            getline(cin, entrada);
            string entrada_trim = trim(entrada);
            if (entrada_trim == "sair" || entrada_trim == "exit" || entrada_trim == "salir") break;
            if (!entrada_trim.empty()) executar(entrada, escopo_local);
        }
    }
    return 0;
}
EOF

# 4. compilação e instalação global
echo "compilando o executável... / compiling executable..."
g++ -O2 pl_linux.cpp -o pl

mv pl /usr/local/bin/pl
chmod +x /usr/local/bin/pl
rm pl_linux.cpp

echo "instalado com sucesso no Linux! / successfully installed on Linux!"
