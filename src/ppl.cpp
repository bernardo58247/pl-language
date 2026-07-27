#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <unordered_map>
#include <regex>
#include <cstdlib>

class InterpretadorPPL {
private:
    std::unordered_map<std::string, std::string> escopo_global;

    std::string aparar(const std::string& str) {
        size_t primeiro = str.find_first_not_of(" \t\r\n");
        if (primeiro == std::string::npos) return "";
        size_t ultimo = str.find_last_not_of(" \t\r\n");
        return str.substr(primeiro, (ultimo - primeiro + 1));
    }

    std::vector<std::string> dividir(const std::string& str, char delimitador) {
        std::vector<std::string> tokens;
        std::string token;
        bool em_aspas = false;

        for (char ch : str) {
            if (ch == '"') em_aspas = !em_aspas;
            if (ch == delimitador && !em_aspas) {
                tokens.push_back(token);
                token.clear();
            } else {
                token += ch;
            }
        }
        tokens.push_back(token);
        return tokens;
    }

    std::string buscar_variavel(const std::string& nome, const std::unordered_map<std::string, std::string>& escopo_local) {
        std::string chave = aparar(nome);
        auto it_local = escopo_local.find(chave);
        if (it_local != escopo_local.end()) return it_local->second;

        auto it_global = escopo_global.find(chave);
        if (it_global != escopo_global.end()) return it_global->second;

        if (chave.front() == '"' && chave.back() == '"') {
            return chave.substr(1, chave.length() - 2);
        }
        return chave;
    }

    std::string formatar_texto(std::string texto, std::unordered_map<std::string, std::string>& escopo_local) {
        for (const auto& [var, val] : escopo_local) {
            std::string alvo = "$" + var;
            size_t pos = 0;
            while ((pos = texto.find(alvo, pos)) != std::string::npos) {
                texto.replace(pos, alvo.length(), val);
                pos += val.length();
            }
        }
        for (const auto& [var, val] : escopo_global) {
            std::string alvo = "$" + var;
            size_t pos = 0;
            while ((pos = texto.find(alvo, pos)) != std::string::npos) {
                texto.replace(pos, alvo.length(), val);
                pos += val.length();
            }
        }
        return texto;
    }

public:
    void executar(const std::string& codigo, std::unordered_map<std::string, std::string> escopo_local = {}) {
        std::vector<std::string> linhas = dividir(codigo, '\n');
        size_t num_linha = 0;

        while (num_linha < linhas.size()) {
            std::string linha_texto = aparar(linhas[num_linha]);
            size_t num_linha_real = num_linha + 1;

            if (linha_texto.empty() || linha_texto.rfind("//", 0) == 0) {
                num_linha++;
                continue;
            }

            try {
                if (linha_texto.rfind("ler.input", 0) == 0) {
                    std::regex padrao_input(R"(ler\.input\s*"(.*?)"(?:\s+para\s+(\w+))?)");
                    std::smatch match;
                    if (std::regex_search(linha_texto, match, padrao_input)) {
                        std::string mensagem = match[1].str();
                        std::string var_destino = match[2].str();
                        std::cout << mensagem;
                        std::string entrada;
                        std::getline(std::cin, entrada);
                        if (!var_destino.empty()) {
                            escopo_local[var_destino] = aparar(entrada);
                        }
                    } else {
                        throw std::runtime_error("formato inválido para ler.input");
                    }
                }
                else if (linha_texto.rfind("se", 0) == 0) {
                    std::regex padrao_se(R"(se\s*\[\s*(\w+)\s*(==|!=)\s*"(.*?)"\s*\]\s*então\s*\((.*?)\)(?:\s*senão\s*\((.*?)\))?)");
                    std::smatch match;
                    if (std::regex_search(linha_texto, match, padrao_se)) {
                        std::string var_nome = match[1].str();
                        std::string operador = match[2].str();
                        std::string valor_comparar = match[3].str();
                        std::string bloco_entao = match[4].str();
                        std::string bloco_senao = match[5].str();

                        std::string valor_var = buscar_variavel(var_nome, escopo_local);
                        bool condicao = (operador == "==") ? (valor_var == valor_comparar) : (valor_var != valor_comparar);

                        if (condicao) {
                            executar(bloco_entao, escopo_local);
                        } else if (!bloco_senao.empty()) {
                            executar(bloco_senao, escopo_local);
                        }
                    } else {
                        throw std::runtime_error("formato inválido para estrutura se/senão");
                    }
                }
                else if (linha_texto.rfind("executar.os", 0) == 0) {
                    std::regex padrao_os(R"(executar\.os\s*"(.*?)"\)");
                    std::smatch match;
                    if (std::regex_search(linha_texto, match, padrao_os)) {
                        std::string cmd_os = formatar_texto(match[1].str(), escopo_local);
                        std::system(cmd_os.c_str());
                    } else {
                        throw std::runtime_error("formato inválido para executar.os");
                    }
                }
                else if (linha_texto.rfind("repetir", 0) == 0) {
                    std::regex padrao_repetir(R"(repetir\s*\((.*?)\)\s*\((\d+|\w+)\))");
                    std::smatch match;
                    if (std::regex_search(linha_texto, match, padrao_repetir)) {
                        std::string bloco_cmds = match[1].str();
                        std::string vezes_str = match[2].str();
                        int vezes = std::stoi(buscar_variavel(vezes_str, escopo_local));

                        for (int i = 0; i < vezes; ++i) {
                            for (const auto& cmd : dividir(bloco_cmds, ';')) {
                                if (!aparar(cmd).empty()) {
                                    executar(aparar(cmd), escopo_local);
                                }
                            }
                        }
                    } else {
                        throw std::runtime_error("formato inválido para repetir");
                    }
                }
                else if (linha_texto.find("definir") != std::string::npos) {
                    std::regex padrao_local(R"(definir\s+(\w+)\s+como\s+variável\s+local\s*=\s*(.+))");
                    std::regex padrao_global(R"(definir\s+(\w+)\s+como\s+variável\s*=\s*(.+))");
                    std::smatch match;

                    if (std::regex_search(linha_texto, match, padrao_local)) {
                        escopo_local[match[1].str()] = buscar_variavel(match[2].str(), escopo_local);
                    } else if (std::regex_search(linha_texto, match, padrao_global)) {
                        escopo_global[match[1].str()] = buscar_variavel(match[2].str(), escopo_local);
                    }
                }
                else if (linha_texto.rfind("mostrar", 0) == 0) {
                    std::string conteudo = aparar(linha_texto.substr(7));
                    std::cout << buscar_variavel(conteudo, escopo_local) << std::endl;
                }
                else {
                    throw std::runtime_error("comando '" + linha_texto + "' não reconhecido");
                }

            } catch (const std::exception& e) {
                std::cerr << "erro de sintaxe (" << e.what() << ") na linha " << num_linha_real << std::endl;
                break;
            }

            num_linha++;
        }
    }
};

int main(int argc, char* argv[]) {
    InterpretadorPPL interpretador;

    if (argc > 1) {
        std::string caminho_arquivo = argv[1];
        std::ifstream arquivo(caminho_arquivo);

        if (arquivo.is_open()) {
            std::string codigo((std::istreambuf_iterator<char>(arquivo)), std::istreambuf_iterator<char>());
            arquivo.close();
            interpretador.executar(codigo);
        } else {
            std::cerr << "erro: arquivo '" << caminho_arquivo << "' não encontrado." << std::endl;
            return 1;
        }
    } else {
        std::cout << "--- PPL (Portuguese Programming Language) ---" << std::endl;
        std::cout << "digite 'sair' para encerrar.\n" << std::endl;

        std::string linha;
        while (true) {
            std::cout << "PPL> ";
            if (!std::getline(std::cin, linha) || linha == "sair") break;
            if (!linha.empty()) {
                interpretador.executar(linha);
            }
        }
    }

    return 0;
}
