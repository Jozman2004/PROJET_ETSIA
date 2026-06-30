const badWords = [
    'merde', 'con', 'pute', 'salope', 'enculé', 'fuck', 'shit',
    'bâtard', 'nique', 'salaud', 'idiot', 'stupid', 'imbécile',
    'haine', 'raciste', 'pédophile', 'viol', 'meurtre', 'putain',
    'connard', 'bordel', 'chier', 'couilles', 'bite', 'nègre',
    'bougnoul', 'pd', 'tarlouze', 'sucer', 'enculer', 'foutre'
];

function containsBadWords(text) {
    const lowerText = text.toLowerCase();
    return badWords.some(badWord => lowerText.includes(badWord));
}

module.exports = (req, res, next) => {
    let textToCheck = '';
    if (req.body.content) textToCheck += req.body.content;
    if (req.body.comment) textToCheck += req.body.comment;
    if (req.body.message) textToCheck += req.body.message;

    if (textToCheck && containsBadWords(textToCheck)) {
        return res.status(400).json({
            error: 'Contenu inapproprié détecté. Veuillez reformuler votre message.'
        });
    }
    next();
};