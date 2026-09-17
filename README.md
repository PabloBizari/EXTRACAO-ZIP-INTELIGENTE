Automação desenvolvida em PowerShell, com o uso de Inteligência Artificial (IA) como apoio no desenvolvimento e aprimoramento da solução, para realizar a extração seletiva de arquivos compactados no formato .zip.

A ferramenta analisa internamente o conteúdo do arquivo compactado e identifica automaticamente o perfil de extração mais adequado com base nas regras previamente configuradas. Dessa forma, são extraídos apenas os documentos necessários, enquanto arquivos que não atendem aos critérios definidos são ignorados.

A automação possui regras específicas para diferentes tipos de documentos, como CCB, histórico de assinatura, documentos de identificação, declarações e arquivos LGPD. Também é possível definir padrões de inclusão e exclusão, evitando, por exemplo, a extração de arquivos com termos como “TERM” ou “ASSINADO”, quando não forem necessários.

O processo utiliza recursos nativos do PowerShell e do .NET, dispensando a instalação de programas externos, como o 7-Zip. Ao final, os arquivos selecionados são extraídos para a pasta de destino informada, com validações de caminho, tratamento de erros e confirmação da quantidade de documentos processados.
