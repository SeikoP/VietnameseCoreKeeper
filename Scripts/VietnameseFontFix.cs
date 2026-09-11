using System;
using System.Collections.Generic;
using System.Text;
using HarmonyLib;
using UnityEngine;

namespace VietnameseFontFix
{
    [HarmonyPatch(typeof(TextManager), "Init2")]
    internal static class VietnameseFontPatch
    {
        private const int Columns = 16;
        private const string Characters =
            "tĂăÂâÊêÔôƠơƯưĐđ" +
            "ÀÁẢÃẠàáảãạÈÉẺẼẸèéẻẽẹÌÍỈĨỊìíỉĩị" +
            "ÒÓỎÕỌòóỏõọÙÚỦŨỤùúủũụỲÝỶỸỴỳýỷỹỵ" +
            "ẦẤẨẪẬầấẩẫậẰẮẲẴẶằắẳẵặ" +
            "ỀẾỂỄỆềếểễệỒỐỔỖỘồốổỗộỜỚỞỠỢờớởỡợ" +
            "ỪỨỬỮỰừứửữự";

        private static readonly Dictionary<int, Dictionary<char, int>> AddedIndices =
            new Dictionary<int, Dictionary<char, int>>();
        private static readonly List<Texture2D> Atlases = new List<Texture2D>();
        private static bool verifiedDotBelow;

        [HarmonyPostfix]
        private static void Postfix(TextManager __instance)
        {
            if (Manager.prefs == null || Manager.prefs.language != "c0")
                return;

            try
            {
                PugFont[] fonts =
                {
                    __instance.thinTiny, __instance.thinSmall, __instance.boldSmall,
                    __instance.thinMedium, __instance.boldMedium, __instance.boldLarge,
                    __instance.boldHuge, __instance.specialBoldLarge, __instance.japaneseFont,
                    __instance.chineseFont, __instance.koreanFont, __instance.buttonFont
                };

                int added = 0;
                foreach (PugFont font in fonts)
                    added += AddGlyphs(font);

                Debug.Log("[VietnameseFontFix] Installed " + added +
                    " native-matched Vietnamese glyphs into Core Keeper PugFonts.");
                if (verifiedDotBelow)
                    Debug.Log("[VietnameseFontFix] Verified native-matched glyph ị with a visible dot below.");
            }
            catch (Exception exception)
            {
                Debug.LogError("[VietnameseFontFix] Install failed: " + exception.Message);
            }
        }

        internal static int AddGlyphs(PugFont font)
        {
            if (font == null || font.texture == null || font.codePoints == null)
                return 0;

            int fontId = font.GetInstanceID();
            Dictionary<char, int> previous;
            if (AddedIndices.TryGetValue(fontId, out previous))
            {
                foreach (KeyValuePair<char, int> pair in previous)
                    font.codePoints[pair.Key] = pair.Value;
                return 0;
            }

            if (!font.codePoints.ContainsKey('a') || !font.codePoints.ContainsKey('i'))
                return 0;

            Texture2D source = MakeReadable(font.texture);
            Color32[] sourcePixels = source.GetPixels32();
            int verticalPadding = 2;
            int cellWidth = Math.Max(8, font.charDims.x);
            int cellHeight = Math.Max(10, font.charDims.y + 2 * verticalPadding);
            int rows = (Characters.Length + Columns - 1) / Columns;
            Texture2D atlas = new Texture2D(Columns * cellWidth, rows * cellHeight,
                TextureFormat.RGBA32, false);
            atlas.filterMode = FilterMode.Point;
            atlas.wrapMode = TextureWrapMode.Clamp;
            Color32[] pixels = new Color32[atlas.width * atlas.height];
            List<PugFont.GlyphData> glyphs = new List<PugFont.GlyphData>(font.glyphData);
            Dictionary<char, int> indices = new Dictionary<char, int>();
            int added = 0;

            for (int characterIndex = 0; characterIndex < Characters.Length; characterIndex++)
            {
                char character = Characters[characterIndex];
                if (font.codePoints.ContainsKey(character) && character != 't')
                    continue;

                bool sourceHasCircumflex;
                char sourceCharacter = GetSourceCharacter(character, font, out sourceHasCircumflex);
                int sourceIndex;
                if (!font.codePoints.TryGetValue(sourceCharacter, out sourceIndex) ||
                    sourceIndex < 0 || sourceIndex >= font.glyphData.Length)
                    continue;

                PugFont.GlyphData template = font.glyphData[sourceIndex];
                Sprite templateSprite = template.volatileSprite;
                if (templateSprite == null)
                    continue;

                int column = characterIndex % Columns;
                int row = characterIndex / Columns;
                int cellX = column * cellWidth;
                int cellY = atlas.height - (row + 1) * cellHeight;
                int sourceHeight = Math.Min(font.charDims.y, (int)templateSprite.rect.height);
                int spriteHeight = sourceHeight + 2 * verticalPadding;
                int sourceWidth = (int)templateSprite.rect.width;
                int copyX = Math.Max(0, (cellWidth - sourceWidth) / 2);

                CopySprite(sourcePixels, source.width, templateSprite, pixels, atlas.width,
                    cellX + copyX, cellY + verticalPadding, sourceHeight);
                int[] bounds = FindInkBounds(pixels, atlas.width, cellX, cellY,
                    cellWidth, spriteHeight);
                DrawMarks(character, sourceHasCircumflex, pixels, atlas.width,
                    cellX, cellY, cellWidth, spriteHeight, bounds, font.charDims.y);

                Vector2 pivot = new Vector2(
                    (copyX + templateSprite.pivot.x) / cellWidth,
                    (verticalPadding + templateSprite.pivot.y) / spriteHeight);
                Sprite sprite = Sprite.Create(atlas,
                    new Rect(cellX, cellY, cellWidth, spriteHeight), pivot,
                    font.pixelsPerUnit, 0, SpriteMeshType.FullRect);
                PugFont.GlyphData glyph = new PugFont.GlyphData
                {
                    rect = template.rect,
                    kerning = template.kerning,
                    volatileSprite = sprite
                };
                int newIndex = glyphs.Count;
                glyphs.Add(glyph);
                font.codePoints[character] = newIndex;
                indices[character] = newIndex;
                added++;
            }

            atlas.SetPixels32(pixels);
            atlas.Apply(false, false);
            UnityEngine.Object.Destroy(source);
            font.glyphData = glyphs.ToArray();
            AddedIndices[fontId] = indices;
            Atlases.Add(atlas);
            return added;
        }

        private static Texture2D MakeReadable(Texture2D texture)
        {
            RenderTexture previous = RenderTexture.active;
            RenderTexture temporary = RenderTexture.GetTemporary(texture.width, texture.height, 0,
                RenderTextureFormat.ARGB32);
            try
            {
                Graphics.Blit(texture, temporary);
                RenderTexture.active = temporary;
                Texture2D copy = new Texture2D(texture.width, texture.height,
                    TextureFormat.RGBA32, false);
                copy.ReadPixels(new Rect(0, 0, texture.width, texture.height), 0, 0);
                copy.Apply(false, false);
                return copy;
            }
            finally
            {
                RenderTexture.active = previous;
                RenderTexture.ReleaseTemporary(temporary);
            }
        }

        private static void CopySprite(Color32[] source, int sourceWidth, Sprite sprite,
            Color32[] target, int targetWidth, int targetX, int targetY, int height)
        {
            int sourceX = (int)sprite.rect.x;
            int sourceY = (int)sprite.rect.y;
            int width = (int)sprite.rect.width;
            for (int y = 0; y < height; y++)
                for (int x = 0; x < width; x++)
                    target[(targetY + y) * targetWidth + targetX + x] =
                        source[(sourceY + y) * sourceWidth + sourceX + x];
        }

        private static int[] FindInkBounds(Color32[] pixels, int textureWidth,
            int xPosition, int yPosition, int width, int height)
        {
            int minX = width, minY = height, maxX = -1, maxY = -1;
            for (int y = 0; y < height; y++)
                for (int x = 0; x < width; x++)
                    if (pixels[(yPosition + y) * textureWidth + xPosition + x].a > 0)
                    {
                        minX = Math.Min(minX, x);
                        minY = Math.Min(minY, y);
                        maxX = Math.Max(maxX, x);
                        maxY = Math.Max(maxY, y);
                    }
            return new[] { minX, minY, maxX, maxY };
        }

        private static void DrawMarks(char character, bool sourceHasCircumflex,
            Color32[] pixels, int textureWidth, int cellX, int cellY, int width,
            int height, int[] bounds, int fontHeight)
        {
            if (bounds[2] < bounds[0])
                return;

            int scale = Math.Max(1, fontHeight / 18);
            int center = (bounds[0] + bounds[2]) / 2;
            string decomposed = character.ToString().Normalize(NormalizationForm.FormD);

            if (character == 't')
            {
                int widestRow = bounds[1];
                int widestCount = -1;
                for (int y = bounds[1]; y <= bounds[3]; y++)
                {
                    int count = 0;
                    for (int x = bounds[0]; x <= bounds[2]; x++)
                        if (pixels[(cellY + y) * textureWidth + cellX + x].a > 0)
                            count++;
                    if (count > widestCount)
                    {
                        widestCount = count;
                        widestRow = y;
                    }
                }
                for (int x = bounds[0]; x <= bounds[2]; x++)
                    if (x - scale >= 0)
                        pixels[(cellY + widestRow) * textureWidth + cellX + x - scale] =
                            pixels[(cellY + widestRow) * textureWidth + cellX + x];
                for (int x = Math.Max(bounds[0], bounds[2] - scale + 1); x <= bounds[2]; x++)
                    pixels[(cellY + widestRow) * textureWidth + cellX + x] =
                        new Color32(0, 0, 0, 0);
                return;
            }

            if (character == 'đ')
            {
                int y = Math.Max(bounds[1], bounds[3] - scale);
                int x = Math.Max(0, bounds[2] - scale);
                int length = Math.Min(width - x, 3 * scale);
                Line(pixels, textureWidth, cellX, cellY, x, y, length, scale);
                return;
            }
            if (character == 'Đ')
            {
                int y = (bounds[1] + bounds[3]) / 2;
                int x = Math.Max(0, bounds[0] - scale);
                int length = Math.Min(width - x, 3 * scale);
                Line(pixels, textureWidth, cellX, cellY, x, y, length, scale);
                return;
            }

            bool hasStructural = false;
            bool hasHorn = decomposed.IndexOf('\u031B') >= 0;
            for (int i = 1; i < decomposed.Length; i++)
                if (decomposed[i] == '\u0302' || decomposed[i] == '\u0306' ||
                    decomposed[i] == '\u031B')
                    hasStructural = true;

            for (int i = 1; i < decomposed.Length; i++)
            {
                char mark = decomposed[i];
                if (sourceHasCircumflex && mark == '\u0302')
                    continue;
                DrawMark(mark, pixels, textureWidth, cellX, cellY, width, height,
                    bounds, center, scale, hasStructural, hasHorn);
            }

            if (character == 'ị')
                for (int y = 0; y < bounds[1]; y++)
                    for (int x = 0; x < width; x++)
                        if (pixels[(cellY + y) * textureWidth + cellX + x].a > 0)
                            verifiedDotBelow = true;
        }

        private static void DrawMark(char mark, Color32[] pixels, int textureWidth,
            int cellX, int cellY, int width, int height, int[] bounds, int center,
            int scale, bool hasStructural, bool hasHorn)
        {
            int top = Math.Min(height - 1, bounds[3] + scale);
            int high = Math.Min(height - 1, top + scale);
            int toneX = hasHorn ? center :
                hasStructural ? Math.Min(width - 2 * scale, bounds[2] + scale) : center;

            switch (mark)
            {
                case '\u0300':
                    Block(pixels, textureWidth, cellX, cellY, toneX - scale, high, scale);
                    Block(pixels, textureWidth, cellX, cellY, toneX, top, scale);
                    break;
                case '\u0301':
                    Block(pixels, textureWidth, cellX, cellY, toneX, top, scale);
                    Block(pixels, textureWidth, cellX, cellY, toneX + scale, high, scale);
                    break;
                case '\u0303':
                    Block(pixels, textureWidth, cellX, cellY, toneX - scale, high, scale);
                    Block(pixels, textureWidth, cellX, cellY, toneX, high, scale);
                    Block(pixels, textureWidth, cellX, cellY, toneX, top, scale);
                    Block(pixels, textureWidth, cellX, cellY, toneX + scale, top, scale);
                    break;
                case '\u0309':
                    Block(pixels, textureWidth, cellX, cellY, toneX, high, scale);
                    Block(pixels, textureWidth, cellX, cellY, toneX + scale, high, scale);
                    Block(pixels, textureWidth, cellX, cellY, toneX + scale, top, scale);
                    break;
                case '\u0323':
                    Block(pixels, textureWidth, cellX, cellY, center,
                        Math.Max(0, bounds[1] - 2 * scale), scale);
                    break;
                case '\u0302':
                    Block(pixels, textureWidth, cellX, cellY, center - scale, top, scale);
                    Block(pixels, textureWidth, cellX, cellY, center, high, scale);
                    Block(pixels, textureWidth, cellX, cellY, center + scale, top, scale);
                    break;
                case '\u0306':
                    Block(pixels, textureWidth, cellX, cellY, center - scale, high, scale);
                    Block(pixels, textureWidth, cellX, cellY, center, top, scale);
                    Block(pixels, textureWidth, cellX, cellY, center + scale, high, scale);
                    break;
                case '\u031B':
                    int hornX = Math.Min(width - scale, bounds[2] + scale);
                    Block(pixels, textureWidth, cellX, cellY, hornX, bounds[3], scale);
                    Block(pixels, textureWidth, cellX, cellY, hornX,
                        Math.Min(height - 1, bounds[3] + scale), scale);
                    break;
            }
        }

        private static void Line(Color32[] pixels, int textureWidth, int cellX,
            int cellY, int x, int y, int length, int thickness)
        {
            for (int i = 0; i < length; i++)
                for (int j = 0; j < thickness; j++)
                    SetPixel(pixels, textureWidth, cellX, cellY, x + i, y + j);
        }

        private static void Block(Color32[] pixels, int textureWidth, int cellX,
            int cellY, int x, int y, int size)
        {
            for (int yy = 0; yy < size; yy++)
                for (int xx = 0; xx < size; xx++)
                    SetPixel(pixels, textureWidth, cellX, cellY, x + xx, y + yy);
        }

        private static void SetPixel(Color32[] pixels, int textureWidth,
            int cellX, int cellY, int x, int y)
        {
            int width = textureWidth / Columns;
            if (x < 0 || x >= width || y < 0)
                return;
            int absoluteY = cellY + y;
            if (absoluteY < 0 || absoluteY >= pixels.Length / textureWidth)
                return;
            pixels[absoluteY * textureWidth + cellX + x] = new Color32(255, 255, 255, 255);
        }

        private static char GetSourceCharacter(char character, PugFont font,
            out bool hasCircumflex)
        {
            hasCircumflex = false;
            if (character == 'Đ') return 'D';
            if (character == 'đ') return 'd';

            string decomposed = character.ToString().Normalize(NormalizationForm.FormD);
            char baseCharacter = decomposed[0];
            if (decomposed.IndexOf('\u0302') >= 0)
            {
                char candidate = CircumflexCharacter(baseCharacter);
                if (candidate != '\0' && font.codePoints.ContainsKey(candidate))
                {
                    hasCircumflex = true;
                    return candidate;
                }
            }
            return baseCharacter;
        }

        private static char CircumflexCharacter(char character)
        {
            switch (character)
            {
                case 'A': return 'Â';
                case 'a': return 'â';
                case 'E': return 'Ê';
                case 'e': return 'ê';
                case 'O': return 'Ô';
                case 'o': return 'ô';
                default: return '\0';
            }
        }
    }

}
