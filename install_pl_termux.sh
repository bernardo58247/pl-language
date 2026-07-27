#!/data/data/com.termux/files/usr/bin/bash

set -e

echo "=== installing PL ==="

# 1. atualiza pacotes e instala dependências necessárias
pkg update -y
pkg install clang termux-api -y

# 2. cria o código-fonte C++ temporário
cat << 'EOF' > pl_termux.cpp
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
        cout << "a linguagem " << lang << " não é suportada por padrão.\n";
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

        // 1. se [ condicao ] então ( comandos senão outros_comandos )
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
        // 2. tocar_som "caminho" (no volume N)
        else if (l.rfind("tocar_som", 0) == 0) {
            regex reg_som("tocar_som\\s*\"(.*?)\"(?:\\s+no\\s+volume\\s+(\\d+|\\w+))?");
            smatch match;
            if (regex_search(l, match, reg_som)) {
                string caminho = formatar_texto(match[1].str(), escopo_local);
                string vol = match[2].matched ? match[2].str() : "";

                ifstream f(caminho.c_str());
                if (!f.good()) {
                    cout << "erro: o arquivo de som '" << caminho << "' não foi encontrado.\n";
                } else {
                    if (!vol.empty()) {
                        string val_vol = buscar_variavel(vol, escopo_local);
                        string cmd_vol = "termux-volume music " + val_vol + " > /dev/null 2>&1";
                        system(cmd_vol.c_str());
                    }
                    string cmd_play = "termux-media-player play \"" + caminho + "\" > /dev/null 2>&1 || mpv --no-terminal \"" + caminho + "\" &";
                    system(cmd_play.c_str());
                }
            }
        }
        // 3. interagir_com "linguagem" (...)
        else if (l.rfind("interagir_com", 0) == 0) {
            regex reg_lang("interagir_com\\s*\"(.*?)\"\\s*\\((.*?)\\)");
            smatch match;
            if (regex_search(l, match, reg_lang)) {
                executar_linguagem_externa(match[1].str(), match[2].str());
            }
        }
        // 4. escolhas "mensagem" (...)
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

                cout << "escolha uma opção: ";
                string resp;
                cin >> resp;
                cin.ignore();
                escopo_local["opcao_escolhida"] = opcoes.count(resp) ? opcoes[resp] : "";
            }
        }
        // 5. ler.input "mensagem"
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
        // 6. executar.os "comando"
        else if (l.rfind("executar.os", 0) == 0) {
            regex reg_os("executar\\.os\\s*\"(.*?)\"");
            smatch match;
            if (regex_search(l, match, reg_os)) {
                string cmd = formatar_texto(match[1].str(), escopo_local);
                system(cmd.c_str());
            }
        }
        // 7. repetir (comandos) (vezes)
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
        // 8. definir variáveis
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
        // 9. mostrar
        else if (l.rfind("mostrar", 0) == 0) {
            string alvo = trim(l.substr(7));
            cout << buscar_variavel(alvo, escopo_local) << "\n";
        }
    }
}

int main(int argc, char* argv[]) {
    map<string, string> escopo_local;

    if (argc > 1) {
        ifstream file(argv[1]);
        if (!file.is_open()) {
            cout << "erro: arquivo '" << argv[1] << "' não encontrado.\n";
            return 1;
        }
        stringstream buffer;
        buffer << file.rdbuf();
        executar(buffer.str(), escopo_local);
    } else {
        cout << "--- PL (Portuguese Language) Nativa [Termux] ---\n";
        cout << "digite 'sair' para encerrar.\n\n";
        string entrada;
        while (true) {
            cout << "PL> ";
            getline(cin, entrada);
            if (trim(entrada) == "sair") break;
            if (!trim(entrada).empty()) executar(entrada, escopo_local);
        }
    }
    return 0;
}
EOF

# 3. compilação nativa
echo "compilando o executável nativo..."
g++ -O2 pl_termux.cpp -o pl

# 4. move para os binários do Termux
DESTINO="/data/data/com.termux/files/usr/bin/pl"
mv pl "$DESTINO"
chmod +x "$DESTINO"

# 5. limpa o código temporário
rm pl_termux.cpp

echo "successfully installed! use pl to start using it!"
